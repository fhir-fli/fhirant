import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// R4B http.html 3.1.0.8.1 (read 2026-10-21, verbatim): a conditional
/// create "can be used to avoid the risk of two clients creating duplicate
/// resources for the same record"; "No matches: The server processes the
/// create as above. One Match: The server ignores the post and returns 200
/// OK". 3.1.0.4.3 conditional update, "No matches, no id provided: The
/// server creates the resource." OWASP ASVS 5.0.0 V15.4.2 (read
/// 2026-10-21): the check and the action that depends on it "are performed
/// as a single atomic operation". Ten conditional creates at once made ten
/// Patients (concurrency_probe, 5 of 5; one at a time, one).
void main() {
  late FhirAntDb db;
  late Handler handler;

  setUp(() async {
    final server = await createTestServer(devMode: true);
    db = server.db;
    handler = server.handler;
  });

  tearDown(() => db.close());

  const json = {
    'content-type': 'application/fhir+json',
    'accept': 'application/fhir+json',
  };
  final patient = {
    'resourceType': 'Patient',
    'identifier': [
      {'system': 'urn:race', 'value': 'one'},
    ],
  };

  Future<int> stored() async {
    final r = await handler(
      testRequest('GET', '/Patient?identifier=urn:race|one', headers: json),
    );
    return (jsonDecode(await r.readAsString()) as Map)['total'] as int;
  }

  Future<List<int>> burst(Request Function() make) async {
    final rs = await Future.wait([
      for (var i = 0; i < 10; i++) Future.sync(() => handler(make())),
    ]);
    return rs.map((r) => r.statusCode).toList()..sort();
  }

  Map<String, dynamic> bundle(String type) => {
        'resourceType': 'Bundle',
        'type': type,
        'entry': [
          {
            'resource': patient,
            'request': {
              'method': 'POST',
              'url': 'Patient',
              'ifNoneExist': 'identifier=urn:race|one',
            },
          },
        ],
      };

  test('POST with If-None-Exist, ten at once: one Patient', () async {
    final statuses = await burst(
      () => testRequest(
        'POST',
        '/Patient',
        body: jsonEncode(patient),
        headers: {...json, 'if-none-exist': 'identifier=urn:race|one'},
      ),
    );
    expect(await stored(), 1, reason: '$statuses');
    expect(statuses, [for (var i = 0; i < 9; i++) 200, 201]);
  });

  test('conditional update with no match, ten at once: one Patient', () async {
    final statuses = await burst(
      () => testRequest(
        'PUT',
        '/Patient?identifier=urn:race|one',
        body: jsonEncode(patient),
        headers: json,
      ),
    );
    expect(await stored(), 1, reason: '$statuses');
  });

  for (final type in ['transaction', 'batch']) {
    test('a $type entry with ifNoneExist, ten Bundles at once: one Patient',
        () async {
      final statuses = await burst(
        () => testRequest(
          'POST',
          '/',
          body: jsonEncode(bundle(type)),
          headers: json,
        ),
      );
      expect(await stored(), 1, reason: '$statuses');
    });
  }
}
