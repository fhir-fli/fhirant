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
}
