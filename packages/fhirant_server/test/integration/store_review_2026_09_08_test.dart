import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/services/backup_service.dart';
import 'package:fhirant_server/src/utils/backup_crypto.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-08 §3 rows 35 and 36 and §4 row 42, through the server
/// and the store as the app uses them.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('store-2026-09-08');
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    token = await issueTestToken(
      db,
      username: 'admin',
      role: 'admin',
      scopes: ['system/*.*'],
    );
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  group('row 36: a tombstone is a column, not a client-writable tag', () {
    test('vread of a live version carrying the DELETED tag is 200', () async {
      await db.saveResource(
        fhir.Patient(
          id: 'tagged'.toFhirString,
          meta: fhir.FhirMeta(
            tag: [
              fhir.Coding(
                system: fhir.FhirUri(HistoryEntry.deletedTagSystem),
                code: fhir.FhirCode('DELETED'),
              ),
            ],
          ),
        ),
      );
      final r = await handler(
        testRequest('GET', '/Patient/tagged/_history/1', authToken: token),
      );
      expect(r.statusCode, 200, reason: await r.readAsString());
      final h = await handler(
        testRequest('GET', '/Patient/tagged/_history', authToken: token),
      );
      final body = jsonDecode(await h.readAsString()) as Map<String, dynamic>;
      final entry = (body['entry'] as List).single as Map<String, dynamic>;
      expect((entry['request'] as Map)['method'], 'POST');
      expect(entry['resource'], isNotNull);
    });

    test('a real delete is a tombstone: vread 410, history DELETE entry',
        () async {
      await db.saveResource(fhir.Patient(id: 'gone'.toFhirString));
      await db.deleteResource(fhir.R4ResourceType.Patient, 'gone');
      final r = await handler(
        testRequest('GET', '/Patient/gone/_history/2', authToken: token),
      );
      expect(r.statusCode, 410, reason: await r.readAsString());
      final h = await handler(
        testRequest('GET', '/Patient/gone/_history', authToken: token),
      );
      final body = jsonDecode(await h.readAsString()) as Map<String, dynamic>;
      final first = (body['entry'] as List).first as Map<String, dynamic>;
      expect((first['request'] as Map)['method'], 'DELETE');
      expect(first['resource'], isNull);
    });
  });

  group('row 35: restore merges accounts by username', () {
    test("the backup's admin survives an id clash with the local admin",
        () async {
      final src = FhirAntDb(NativeDatabase(File('${tmp.path}/src.sqlite')));
      await src.initialize();
      final salt = PasswordHasher.generateSalt();
      await src.createUser(
        username: 'alice',
        passwordHash: PasswordHasher.hashPassword('alice-password-123', salt),
        salt: salt,
        role: 'admin',
      );
      await src.createUser(
        username: 'admin',
        passwordHash: PasswordHasher.hashPassword('other-password-123', salt),
        salt: salt,
      );
      await src.saveResource(fhir.Patient(id: 'from-backup'.toFhirString));
      final file = await BackupService.createFile(
        src,
        'correct horse battery',
        '${tmp.path}/bk.sqlite',
      );
      await src.close();

      // Locally: 'admin' (id 1, created by issueTestToken) holds the id the
      // backup's 'alice' had.
      final localAdmin = await db.getUserByUsername('admin');
      expect(localAdmin!.id, 1);

      final restored = await db.restoreEncrypted(
        file.path,
        'correct horse battery',
      );
      expect(restored, 1);
      final alice = await db.getUserByUsername('alice');
      expect(alice, isNotNull, reason: 'the backup admin was dropped');
      expect(alice!.role, 'admin');
      expect(alice.id, isNot(1), reason: 'renumbered past the local admin');
      // Same username: the local account stands, password included.
      final admin = await db.getUserByUsername('admin');
      expect(admin!.id, 1);
      expect(admin.role, 'admin');
      expect(await db.getUserCount(), 2);
    });

    test('a backup account whose id is free keeps it', () async {
      final src = FhirAntDb(NativeDatabase(File('${tmp.path}/src2.sqlite')));
      await src.initialize();
      final salt = PasswordHasher.generateSalt();
      await src.createUser(
        username: 'first',
        passwordHash: 'h',
        salt: salt,
      );
      await src.createUser(
        username: 'second',
        passwordHash: 'h',
        salt: salt,
      );
      final file = await BackupService.createFile(
        src,
        'correct horse battery',
        '${tmp.path}/bk2.sqlite',
      );
      await src.close();
      await db.restoreEncrypted(file.path, 'correct horse battery');
      // Local id 1 is 'admin'; the backup's id 1 ('first') is renumbered,
      // its id 2 ('second') is free and kept.
      expect((await db.getUserByUsername('second'))!.id, 2);
      expect((await db.getUserByUsername('first'))!.id, greaterThan(2));
    });
  });

  group('row 42: the envelope check reads the head of the file', () {
    test('an encrypted envelope is recognised from its first bytes', () async {
      final envelope = File('${tmp.path}/env.json')
        ..writeAsStringSync(
          BackupCrypto.encrypt(
            '{"resourceType":"Bundle"}',
            'passphrase-long-enough',
          ),
        );
      expect(await BackupService.isEncryptedFile(envelope.path), isTrue);
      final plain = File('${tmp.path}/plain.json')
        ..writeAsStringSync('{"resourceType":"Bundle","type":"collection"}');
      expect(await BackupService.isEncryptedFile(plain.path), isFalse);
      final sqlite = File('${tmp.path}/x.sqlite')
        ..writeAsBytesSync(List<int>.generate(64, (i) => i * 3 % 251));
      expect(await BackupService.isEncryptedFile(sqlite.path), isFalse);
    });
  });
}
