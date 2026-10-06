import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:test/test.dart';

import '../integration/test_helpers.dart';

/// REVIEW-2026-10-06 finding 11 (probe P9): `GET /Patient?name=x` was
/// audited as subtype `read`, action `R`, the same as a read of one record,
/// and `GET /?_type=Patient` (the system search, R4B search.html 3.1.1.2)
/// was not audited at all. The restful-interaction code system (R4B
/// valueset-restful-interaction, read 2026-10-06) has `search-type`,
/// `search-system` and `search-compartment` for the three.
void main() {
  late FhirAntDb db;
  late FhirAntServer server;
  late String admin;

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
    server = FhirAntServer(db, jwtSecret: testJwtSecret);
    admin = await issueTestToken(
      db,
      username: 'adm',
      role: 'admin',
      scopes: ['system/*.*'],
    );
  });

  tearDown(() => db.close());

  Future<List<(String, String)>> auditedAs(
    String method,
    String path, {
    String? body,
    Map<String, String>? headers,
  }) async {
    final handler = server.createHandler(server.createRouter());
    await handler(
      testRequest(method, path, authToken: admin, body: body, headers: headers),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await server.auditQueue.drain();
    final events = await db.getResourcesByType(fhir.R4ResourceType.AuditEvent);
    return [
      for (final e in events.whereType<fhir.AuditEvent>())
        (e.subtype!.first.code!.valueString!, e.action!.valueString!),
    ];
  }

  test('a type-level GET is search-type', () async {
    expect(await auditedAs('GET', '/Patient?name=x'), [('search-type', 'R')]);
  });

  test('a POST _search on a type is search-type', () async {
    expect(
      await auditedAs(
        'POST',
        '/Patient/_search',
        body: 'name=x',
        headers: {'content-type': 'application/x-www-form-urlencoded'},
      ),
      [('search-type', 'R')],
    );
  });

  test('a system search, GET /?… or POST /_search, is search-system', () async {
    expect(await auditedAs('GET', '/?_type=Patient'), [('search-system', 'R')]);
  });

  test('a bare GET / is still not audited', () async {
    expect(await auditedAs('GET', '/'), isEmpty);
  });

  test('a compartment search is search-compartment', () async {
    await db.saveResource(fhir.Patient(id: fhir.FhirString('p1')));
    expect(
      await auditedAs('GET', '/Patient/p1/Observation'),
      [('search-compartment', 'R')],
    );
  });

  test('a read of one record stays read', () async {
    expect(await auditedAs('GET', '/Patient/p1'), [('read', 'R')]);
  });
}
