import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-17 Q7. A Bundle entry URL was split on `/` and its first
/// two segments taken, so `GET Patient/p1/_history` in a batch answered the
/// Patient, and so did `Patient/p1/$everything`. This server processes
/// `[type]` and `[type]/[id]`, either with a query, inside a Bundle; any
/// other shape is refused as unsupported, entry by entry.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;
  late Directory exportDir;

  setUp(() async {
    exportDir = await Directory.systemTemp.createTemp('entry-url');
    final server = await createTestServer(exportDir: exportDir.path);
    db = server.db;
    handler = server.handler;
    token = await issueTestToken(
      db,
      username: 'admin',
      role: 'admin',
      scopes: ['system/*.*'],
    );
    await db.saveResource(fhir.Patient(id: 'p1'.toFhirString));
  });

  tearDown(() async {
    await db.close();
    await exportDir.delete(recursive: true);
  });

  Future<List<Map<String, dynamic>>> batch(List<String> urls) async {
    final r = await handler(
      testRequest(
        'POST',
        '/',
        authToken: token,
        headers: {'content-type': 'application/fhir+json'},
        body: jsonEncode({
          'resourceType': 'Bundle',
          'type': 'batch',
          'entry': [
            for (final url in urls)
              {
                'request': {'method': 'GET', 'url': url},
              },
          ],
        }),
      ),
    );
    final text = await r.readAsString();
    expect(r.statusCode, 200, reason: text);
    return ((jsonDecode(text) as Map<String, dynamic>)['entry'] as List)
        .cast<Map<String, dynamic>>();
  }

  test('a URL that is not [type] or [type]/[id] is refused, not truncated',
      () async {
    final entries = await batch([
      'Patient/p1/_history',
      r'Patient/p1/$everything',
      r'Patient/$validate',
      'Patient/_history',
      'Patient/p1/Observation',
      'Patient/p1',
    ]);
    for (final entry in entries.take(5)) {
      expect(
        (entry['response'] as Map)['status'],
        '400',
        reason: jsonEncode(entry),
      );
      expect(entry, isNot(contains('resource')));
      expect(
        jsonEncode((entry['response'] as Map)['outcome']),
        contains('not an interaction this server processes inside a Bundle'),
      );
    }
    final read = entries.last;
    expect((read['response'] as Map)['status'], '200');
    expect((read['resource'] as Map)['id'], 'p1');
  });
}
