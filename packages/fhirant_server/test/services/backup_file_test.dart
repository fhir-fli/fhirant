import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/services/backup_service.dart';
import 'package:fhirant_server/src/utils/backup_crypto.dart';
import 'package:test/test.dart';

/// The whole database as one passphrase-encrypted SQLite file
/// (REVIEW-2026-09-06 finding 33), on the sqlite3mc build this package
/// tests on: written by `BackupService.createFile`, merged back by
/// `restoreFile`, unreadable without the passphrase.
void main() {
  late Directory dir;
  late FhirAntDb db;

  fhir.Patient patient(String id, String family) => fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': id,
        'name': [
          {'family': family},
        ],
      });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fhirant_backup_');
    db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<List<String>> families(FhirAntDb d) async => (await d.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'family': <String>['a'],
        },
        sort: ['_id'],
      ))
          .map((r) => (r as fhir.Patient).name!.single.family!.valueString!)
          .toList();

  /// A backup is a store file under the passphrase (SQLCipher 4 format,
  /// REVIEW-2026-09-17 R1), so it opens the way a store does.
  FhirAntDb openCopy(String path, String passphrase) => FhirAntDb(
        NativeDatabase(
          File(path),
          setup: (raw) => applyStoreCipher(raw, passphrase),
        ),
      );

  test('this build has the cipher', () async {
    final rows = await db.customSelect('PRAGMA cipher').get();
    expect(rows, isNotEmpty);
  });

  test('the file opens with the passphrase and carries everything', () async {
    await db.saveResource(patient('p1', 'Alpha'));
    await db.saveResource(patient('p1', 'Alpha two'));
    await db.saveResource(patient('p2', 'Amber'));
    await db.createUser(username: 'grey', passwordHash: 'h', salt: 's');
    final file = await BackupService.createFile(
      db,
      'correct horse',
      '${dir.path}/backup.sqlite',
    );

    final copy = openCopy(file.path, 'correct horse');
    expect(await families(copy), ['Alpha two', 'Amber']);
    expect(
      (await copy.getResourceHistory(fhir.R4ResourceType.Patient, 'p1'))
          .map((r) => r.meta!.versionId!.valueString),
      ['2', '1'],
    );
    expect((await copy.getUserByUsername('grey'))?.username, 'grey');
    final version = await copy.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.first, db.schemaVersion);
    // No indexes travel: the restore reads tables, and a backup opened as a
    // database builds them on request.
    Future<int> indexes() async => (await copy
            .customSelect(
              "SELECT count(*) AS c FROM sqlite_master WHERE type = 'index' "
              "AND name LIKE 'idx_%'",
            )
            .getSingle())
        .read<int>('c');
    expect(await indexes(), 0);
    await copy.createValueIndexes();
    expect(await indexes(), greaterThan(20));
    await copy.close();
  });

  test(
      'without the passphrase the file is not a database, and holds no '
      'readable data', () async {
    await db.saveResource(patient('p1', 'Alpha'));
    final file = await BackupService.createFile(
      db,
      'correct horse',
      '${dir.path}/backup.sqlite',
    );
    final bytes = await file.readAsBytes();
    expect(String.fromCharCodes(bytes.take(16)), isNot(contains('SQLite')));
    expect(String.fromCharCodes(bytes), isNot(contains('Alpha')));
    expect(await BackupService.isJsonFile(file.path), isFalse);

    final other = FhirAntDb(NativeDatabase.memory());
    await other.initialize();
    await expectLater(
      BackupService.restoreFile(other, file.path, passphrase: 'wrong'),
      throwsA(isA<BackupDecryptionException>()),
    );
    await expectLater(
      BackupService.restoreFile(other, file.path),
      throwsA(isA<BackupPassphraseRequired>()),
    );
    await other.close();
  });

  test('a restore onto an empty device is the backup', () async {
    await db.saveResource(patient('p1', 'Alpha'));
    await db.saveResource(patient('p2', 'Amber'));
    await db.deleteResource(fhir.R4ResourceType.Patient, 'p2');
    await db.createUser(username: 'grey', passwordHash: 'h', salt: 's');
    final file = await BackupService.createFile(
      db,
      'correct horse',
      '${dir.path}/backup.sqlite',
    );

    final fresh = FhirAntDb(NativeDatabase.memory());
    await fresh.initialize();
    final result = await BackupService.restoreFile(
      fresh,
      file.path,
      passphrase: 'correct horse',
    );
    expect(result.saved, 1);
    expect(result.failures, isEmpty);
    expect(await families(fresh), ['Alpha']);
    expect(
      (await fresh.getHistory(fhir.R4ResourceType.Patient, 'p2'))
          .map((e) => e.deleted),
      [true, false],
    );
    expect((await fresh.getUserByUsername('grey'))?.username, 'grey');
    await fresh.close();
  });

  test(
      'onto a device with data: the backup wins on a resource, local '
      'accounts stay', () async {
    await db.saveResource(patient('p1', 'Alpha'));
    final file = await BackupService.createFile(
      db,
      'correct horse',
      '${dir.path}/backup.sqlite',
    );

    final target = FhirAntDb(NativeDatabase.memory());
    await target.initialize();
    await target.saveResource(patient('p1', 'Anders'));
    await target.saveResource(patient('p3', 'Arne'));
    final localUser = await target.createUser(
      username: 'local',
      passwordHash: 'h',
      salt: 's',
    );
    expect(await target.restoreEncrypted(file.path, 'correct horse'), 1);
    // p1 is the backup's, index rows included: the search finds the backup
    // spelling and not the local one; p3 is untouched.
    expect(await families(target), ['Alpha', 'Arne']);
    expect(
      await target.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'family': <String>['Anders'],
        },
      ),
      isEmpty,
    );
    expect((await target.getUserById(localUser))?.username, 'local');
    await target.close();
  });

  test('a restore over a newer local version is a new version, history kept',
      () async {
    // REVIEW-2026-09-17 D1. The restore used to INSERT OR REPLACE: a local
    // v3 became the backup's v1, v3 was never moved to history, and the
    // next saves (v2, v3 again) upserted history over the local rows.
    await db.saveResource(patient('p1', 'Alpha'));
    final file = await BackupService.createFile(
      db,
      'correct horse',
      '${dir.path}/backup.sqlite',
    );

    final target = FhirAntDb(NativeDatabase.memory());
    await target.initialize();
    await target.saveResource(patient('p1', 'Local one'));
    await target.saveResource(patient('p1', 'Local two'));
    await target.saveResource(patient('p1', 'Local three'));

    expect(await target.restoreEncrypted(file.path, 'correct horse'), 1);

    final current = await target.getResource(fhir.R4ResourceType.Patient, 'p1');
    expect(
      (current! as fhir.Patient).name!.single.family!.valueString,
      'Alpha',
      reason: 'the backup wins on the resource',
    );
    expect(current.meta!.versionId!.valueString, '4');
    expect(
      (await target.getResourceHistory(fhir.R4ResourceType.Patient, 'p1'))
          .map((r) => r.meta!.versionId!.valueString),
      ['4', '3', '2', '1'],
      reason: 'nothing local is lost',
    );
    // And the next save counts on, over nothing.
    final next = await target.saveResource(patient('p1', 'After'));
    expect(next!.meta!.versionId!.valueString, '5');
    expect(
      (await target.getResourceHistory(fhir.R4ResourceType.Patient, 'p1'))
          .map((r) => r.meta!.versionId!.valueString),
      ['5', '4', '3', '2', '1'],
    );
    await target.close();
  });

  test('a backup from a newer schema is refused before anything is read',
      () async {
    await db.saveResource(patient('p1', 'Alpha'));
    final file = await BackupService.createFile(
      db,
      'correct horse',
      '${dir.path}/backup.sqlite',
    );
    final future = openCopy(file.path, 'correct horse');
    await future.customStatement('PRAGMA user_version = 99');
    await future.close();
    await expectLater(
      db.restoreEncrypted(file.path, 'correct horse'),
      throwsA(isA<BackupSchemaTooNew>()),
    );
  });

  test('an encrypted backup that happens to start with "{" is not JSON',
      () async {
    // SQLCipher's file begins with a random 16-byte salt, so one backup in
    // 256 starts with 0x7B. The detector looked at that byte alone and the
    // restore then read the file as UTF-8 and threw a FileSystemException
    // instead of the wrong-passphrase answer (seen once in a suite run,
    // 2026-09-18). Built here deterministically: `{` and then bytes no
    // UTF-8 text contains.
    final file = File('${dir.path}/unlucky.sqlite')
      ..writeAsBytesSync([0x7B, ...List.filled(4095, 0xFF)]);
    expect(await BackupService.isJsonFile(file.path), isFalse);
    await expectLater(
      BackupService.restoreFile(db, file.path, passphrase: 'wrong'),
      throwsA(isA<BackupDecryptionException>()),
    );
  });

  test('a JSON file with a character cut by the 64-byte window is JSON',
      () async {
    // 62 ASCII bytes, then a two-byte character straddling byte 64.
    const json = '{"resourceType":"Bundle","type":"collection","id":"éééééé"}';
    final file = File('${dir.path}/cut.json')..writeAsStringSync(json);
    expect(utf8.encode(json).length, greaterThan(64));
    expect(await BackupService.isJsonFile(file.path), isTrue);
  });

  test(
      'a Bundle envelope and a plain Bundle still restore through the '
      'same door', () async {
    await db.saveResource(patient('p1', 'Alpha'));
    final envelope = File('${dir.path}/backup.json')
      ..writeAsStringSync(await BackupService.create(db, 'correct horse'));
    expect(await BackupService.isJsonFile(envelope.path), isTrue);
    final fresh = FhirAntDb(NativeDatabase.memory());
    await fresh.initialize();
    final result = await BackupService.restoreFile(
      fresh,
      envelope.path,
      passphrase: 'correct horse',
    );
    expect(result.saved, 1);
    expect(await families(fresh), ['Alpha']);
    await fresh.close();
  });
}
