import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:test/test.dart';

/// REVIEW-2026-09-17 A16: AuditEvents had no retention; every read wrote
/// one and nothing removed any. The hourly sweep purges those older than
/// [FhirAntServer.auditRetention] when a deployment sets one, with their
/// history and index rows; unset, it deletes nothing.
void main() {
  late FhirAntDb db;

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
  });
  tearDown(() => db.close());

  fhir.AuditEvent event(String id) => fhir.AuditEvent.fromJson({
        'resourceType': 'AuditEvent',
        'id': id,
        'type': {
          'system': 'http://dicom.nema.org/resources/ontology/DCM',
          'code': '110112',
        },
        'recorded': '2026-09-19T00:00:00Z',
        'agent': [
          {'requestor': true},
        ],
        'source': {
          'observer': {'display': 'test'},
        },
      });

  /// The store stamps `last_updated` at save; a row is aged by hand.
  Future<void> age(String id, Duration by) async {
    final at = DateTime.now().toUtc().subtract(by).millisecondsSinceEpoch;
    for (final table in ['resources', 'resources_history']) {
      await db.customStatement(
        'UPDATE $table SET last_updated = ? WHERE resource_type = ? '
        'AND id = ?',
        [at, 'AuditEvent', id],
      );
    }
  }

  Future<int> rowsIn(String table, String id) async => (await db.customSelect(
        'SELECT count(*) AS n FROM $table WHERE resource_type = ? AND id = ?',
        variables: [Variable.withString('AuditEvent'), Variable.withString(id)],
      ).getSingle())
          .read<int>('n');

  Future<int> historyRows(String id) => rowsIn('resources_history', id);

  Future<int> indexRows(String id) => rowsIn('token_search_parameters', id);

  test('the sweep removes events past the retention, rows, history and index',
      () async {
    await db.saveResources([event('old'), event('recent')]);
    await age('old', const Duration(days: 40));
    await age('recent', const Duration(days: 20));
    expect(await indexRows('old'), greaterThan(0), reason: 'indexed');

    final server = FhirAntServer(
      db,
      jwtSecret: 'test-secret',
      auditRetention: const Duration(days: 30),
    );
    await server.hourlyCleanup();

    final left = await db.search(resourceType: fhir.R4ResourceType.AuditEvent);
    expect(left.map((r) => r.id!.valueString), ['recent']);
    expect(await historyRows('old'), 0);
    expect(await indexRows('old'), 0);
    // A first version writes no history row; the current row is enough.
    expect(await rowsIn('resources', 'recent'), 1);
  });

  test('with no retention configured, the sweep deletes nothing', () async {
    // No source sets a retention period for audit records (see
    // FhirAntServer.auditRetention), so the default removes none, however
    // old.
    await db.saveResources([event('ancient')]);
    await age('ancient', const Duration(days: 20 * 365));
    await FhirAntServer(db, jwtSecret: 'test-secret').hourlyCleanup();
    final left = await db.search(resourceType: fhir.R4ResourceType.AuditEvent);
    expect(left, hasLength(1));
  });
}
