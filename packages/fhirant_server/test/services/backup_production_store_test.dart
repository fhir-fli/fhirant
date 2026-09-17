import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/services/backup_service.dart';
import 'package:fhirant_server/src/utils/backup_crypto.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;
import 'package:test/test.dart';

/// The encrypted backup, from and into a store opened the way the CLI
/// (`bin/server.dart`) and the app (`database_service.dart`) open theirs:
/// a file, `PRAGMA cipher`, `PRAGMA legacy = 4`, `PRAGMA key`.
///
/// REVIEW-2026-09-17 R1: every other backup test builds its store with
/// `NativeDatabase.memory()` and no cipher pragmas, and with that store the
/// round trip works. sqlite3mc (SQL Pragmas page, read whole 2026-09-17):
/// a cipher PRAGMA with no schema name "affects the default values of the
/// encryption parameters", and `ATTACH … KEY` takes those defaults, so a
/// production store wrote its backup with `legacy = 4` and
/// `restoreEncrypted` opened it without: "file is not a database",
/// reported to the operator as a wrong passphrase.
void main() {
  late Directory dir;

  fhir.Patient patient(String id, String family) => fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': id,
        'name': [
          {'family': family},
        ],
      });

  /// A store opened by [openStore], the function the CLI and the app use.
  Future<FhirAntDb> production(String name) async {
    final db = FhirAntDb(
      NativeDatabase(
        File('${dir.path}/$name'),
        setup: (raw) => applyStoreCipher(raw, 'the-store-key'),
      ),
    );
    await db.initialize();
    return db;
  }

  Future<List<String>> families(FhirAntDb d) async => (await d.search(
        resourceType: fhir.R4ResourceType.Patient,
        sort: ['_id'],
      ))
          .map((r) => (r as fhir.Patient).name!.single.family!.valueString!)
          .toList();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fhirant_backup_prod_');
  });
  tearDown(() => dir.delete(recursive: true));

  test('the store function sets what the stores have always been opened with',
      () async {
    final db = await production('main.db');
    Future<String> pragma(String name) async =>
        '${(await db.customSelect('PRAGMA $name').getSingle()).data.values.first}';
    expect(await pragma('cipher'), 'sqlcipher');
    expect(await pragma('legacy'), '4');
    await db.close();
    // Encrypted: the file does not open without the key.
    final raw = sqlite3.open('${dir.path}/main.db');
    expect(
      () => raw.select('SELECT count(*) FROM resources'),
      throwsA(anything),
    );
    raw.close();
  });

  test('a production store backs up and restores into a production store',
      () async {
    final source = await production('source.db');
    await source.saveResource(patient('p1', 'Alpha'));
    await source.saveResource(patient('p2', 'Amber'));
    final file = await BackupService.createFile(
      source,
      'correct horse',
      '${dir.path}/backup.sqlite',
    );

    final target = await production('target.db');
    final result = await BackupService.restoreFile(
      target,
      file.path,
      passphrase: 'correct horse',
    );
    expect(result.saved, 2);
    expect(await families(target), ['Alpha', 'Amber']);

    // And into the store it came from.
    expect(await source.restoreEncrypted(file.path, 'correct horse'), 2);
    await source.close();
    await target.close();
  });

  test('the backup is one format whatever store wrote it', () async {
    final prod = await production('source.db');
    await prod.saveResource(patient('p1', 'Alpha'));
    final plain = FhirAntDb(NativeDatabase.memory());
    await plain.initialize();
    await plain.saveResource(patient('p2', 'Amber'));

    final fromProd = '${dir.path}/from-prod.sqlite';
    final fromPlain = '${dir.path}/from-plain.sqlite';
    await prod.copyEncrypted(fromProd, 'correct horse');
    await plain.copyEncrypted(fromPlain, 'correct horse');

    // Both open as SQLCipher 4 files, the format the stores themselves
    // are in, with nothing else configured.
    for (final path in [fromProd, fromPlain]) {
      final raw = sqlite3.open(path)
        ..execute("PRAGMA cipher = 'sqlcipher'")
        ..execute('PRAGMA legacy = 4')
        ..execute("PRAGMA key = 'correct horse'");
      expect(
        raw.select('SELECT count(*) AS c FROM resources').first['c'],
        1,
        reason: path,
      );
      raw.close();
    }

    // Each restores into the other kind of store.
    expect(await plain.restoreEncrypted(fromProd, 'correct horse'), 1);
    expect(await prod.restoreEncrypted(fromPlain, 'correct horse'), 1);
    expect(await families(plain), ['Alpha', 'Amber']);
    expect(await families(prod), ['Alpha', 'Amber']);
    await prod.close();
    await plain.close();
  });

  test(
      'a backup written before this fix by a store with no legacy setting '
      'still restores', () async {
    // What `copyEncrypted` used to do on a connection whose cipher defaults
    // were never set (every test store, and any store opened without
    // `legacy`): a bare ATTACH … KEY.
    final old = FhirAntDb(NativeDatabase.memory());
    await old.initialize();
    await old.saveResource(patient('p1', 'Alpha'));
    final path = '${dir.path}/old-format.sqlite';
    await old.customStatement("PRAGMA cipher = 'sqlcipher'");
    await old
        .customStatement("ATTACH DATABASE '$path' AS bk KEY 'correct horse'");
    final tables = await old
        .customSelect(
          "SELECT name, sql FROM main.sqlite_master WHERE type = 'table' "
          "AND sql IS NOT NULL AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    for (final t in tables) {
      final name = t.read<String>('name');
      await old.customStatement(
        t.read<String>('sql').replaceFirst(
              RegExp('^CREATE TABLE\\s+(IF NOT EXISTS\\s+)?"?$name"?'),
              'CREATE TABLE bk."$name"',
            ),
      );
      await old.customStatement(
        'INSERT INTO bk."$name" SELECT * FROM main."$name"',
      );
    }
    await old.customStatement('PRAGMA bk.user_version = ${old.schemaVersion}');
    await old.customStatement('DETACH DATABASE bk');
    await old.close();

    final target = await production('target.db');
    expect(await target.restoreEncrypted(path, 'correct horse'), 1);
    expect(await families(target), ['Alpha']);
    await target.close();
  });

  test('a wrong passphrase is still refused, from a production store',
      () async {
    final source = await production('source.db');
    await source.saveResource(patient('p1', 'Alpha'));
    final file = await BackupService.createFile(
      source,
      'correct horse',
      '${dir.path}/backup.sqlite',
    );
    await expectLater(
      BackupService.restoreFile(source, file.path, passphrase: 'wrong horse'),
      throwsA(isA<BackupDecryptionException>()),
    );
    await source.close();
  });
}
