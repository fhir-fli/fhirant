import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:test/test.dart';

/// createUser returns the id of the row it inserted. It ran the INSERT,
/// then `SELECT last_insert_rowid()` as a second statement; that function
/// reports the connection's most recent insert into any table, so a write
/// landing between the two was answered instead: 100 overlapping calls,
/// 99 wrong ids, 5 of 5 runs (fhirant_server tool/review_2026-10-17/
/// register_race/create_user_ids_probe.tsv; OWASP ASVS 5.0.0 V15.4.2).
void main() {
  late FhirAntDb db;

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
  });

  tearDown(() => db.close());

  test('overlapping calls each get their own row', () async {
    final names = [for (var k = 0; k < 100; k++) 'user$k'];
    final ids = await Future.wait([
      for (final n in names)
        db.createUser(username: n, passwordHash: 'h', salt: 's'),
    ]);
    for (var k = 0; k < names.length; k++) {
      expect(
        ids[k],
        (await db.getUserByUsername(names[k]))!.id,
        reason: names[k],
      );
    }
  });

  test('a resource saved in between does not change the id', () async {
    final both = await Future.wait<Object>([
      db.createUser(username: 'alone', passwordHash: 'h', salt: 's'),
      db.saveResource(const fhir.Patient()),
    ]);
    expect(both.first, (await db.getUserByUsername('alone'))!.id);
  });

  // The store's UNIQUE constraint is the check two registrations at once
  // cannot both pass; the CLI's store raises it as a SqliteException, the
  // app's background store wraps it in a DriftRemoteException (measured
  // 2026-10-21). Either way it is UsernameTaken.
  test('a duplicate username is UsernameTaken, on this isolate', () async {
    await db.createUser(username: 'dup', passwordHash: 'h', salt: 's');
    expect(
      () => db.createUser(username: 'dup', passwordHash: 'h', salt: 's'),
      throwsA(isA<UsernameTaken>()),
    );
  });

  test('a duplicate username is UsernameTaken, from a background store',
      () async {
    final dir = await Directory.systemTemp.createTemp('fhirant_db_dup_');
    final background = FhirAntDb(
      NativeDatabase.createInBackground(File('${dir.path}/x.db')),
    );
    addTearDown(() async {
      await background.close();
      await dir.delete(recursive: true);
    });
    await background.initialize();
    await background.createUser(username: 'dup', passwordHash: 'h', salt: 's');
    await expectLater(
      background.createUser(username: 'dup', passwordHash: 'h', salt: 's'),
      throwsA(isA<UsernameTaken>()),
    );
  });
}
