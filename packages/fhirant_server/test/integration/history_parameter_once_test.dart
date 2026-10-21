import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// R4B http.html 3.1.0.10 history (hl7.org/fhir/R4B/http.html, read
/// 2026-10-20, verbatim), after the table of `_count`, `_since`, `_at` and
/// `_list`: "Each of these parameters SHALL NOT appear more than once."
/// REVIEW-2026-10-17 (smaller list): `_count` given twice answered 200,
/// with both values in the self link and one of them applied.
void main() {
  late FhirAntDb db;
  late Handler handler;

  setUp(() async {
    final server = await createTestServer(devMode: true);
    db = server.db;
    handler = server.handler;
    await db.saveResource(
      fhir.Resource.fromJson({'resourceType': 'Patient', 'id': 'h1'}),
    );
  });

  tearDown(() => db.close());

  Future<Response> get(String path) async => handler(
        testRequest(
          'GET',
          path,
          headers: {'accept': 'application/fhir+json'},
        ),
      );

  const levels = ['/Patient/h1/_history', '/Patient/_history', '/_history'];
  const repeated = {
    '_count': '_count=1&_count=2',
    '_since': '_since=2026-01-01T00:00:00Z&_since=2026-02-01T00:00:00Z',
    '_at': '_at=2026-01-01T00:00:00Z&_at=2026-02-01T00:00:00Z',
    '_list': '_list=a&_list=b',
  };

  for (final level in levels) {
    for (final MapEntry(key: name, value: query) in repeated.entries) {
      test('$level: $name twice is refused', () async {
        final r = await get('$level?$query');
        expect(r.statusCode, 400);
        final body = jsonDecode(await r.readAsString()) as Map;
        expect(body['resourceType'], 'OperationOutcome');
        expect(jsonEncode(body), contains(name));
      });
    }

    test('control: $level with each parameter once is answered', () async {
      final r = await get('$level?_count=2&_since=2026-01-01T00:00:00Z');
      expect(r.statusCode, 200, reason: await r.readAsString());
    });
  }
}
