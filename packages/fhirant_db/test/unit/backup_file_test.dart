import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:test/test.dart';

/// The whole database as one passphrase-encrypted SQLite file
/// (REVIEW-2026-09-06 finding 33). This package's tests run on plain SQLite,
/// which has no cipher: `PRAGMA key` and `ATTACH … KEY` parse and do nothing,
/// and the first version of `copyEncrypted` wrote a plaintext file here and
/// reported success. So what this build proves is the refusal; the round
/// trip is proved in fhirant_server, whose tests are built on sqlite3mc.
void main() {
  late Directory dir;
  late FhirAntDb db;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fhirant_backup_');
    db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('a build without a cipher writes no backup', () async {
    final path = '${dir.path}/backup.sqlite';
    final cipher = await db.customSelect('PRAGMA cipher').get();
    expect(cipher, isEmpty, reason: 'this test suite runs on plain SQLite');
    await expectLater(
      db.copyEncrypted(path, 'correct horse'),
      throwsA(isA<NoCipherInThisBuild>()),
    );
    expect(File(path).existsSync(), isFalse);
  });

  test('a build without a cipher restores no backup either', () async {
    final path = '${dir.path}/backup.sqlite';
    File(path).writeAsBytesSync(List.filled(4096, 0));
    await expectLater(
      db.restoreEncrypted(path, 'correct horse'),
      throwsA(isA<NoCipherInThisBuild>()),
    );
  });

  test('an empty passphrase or a missing file is refused before anything',
      () async {
    await expectLater(
      db.copyEncrypted('${dir.path}/x.sqlite', ''),
      throwsArgumentError,
    );
    await expectLater(
      db.restoreEncrypted('${dir.path}/absent.sqlite', 'p'),
      throwsArgumentError,
    );
  });
}
