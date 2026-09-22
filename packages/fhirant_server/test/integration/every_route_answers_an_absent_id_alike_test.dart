@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// Every route that names a resource in its URL answers an id the store
/// does not hold the same way: 404, `application/fhir+json`, an
/// OperationOutcome whose issue code is `not-found`.
///
/// R4B http.html, read whole 2026-09-22, verbatim: "a GET for an unknown
/// resource returns 404"; and "The correct mime type SHALL be used by
/// clients and servers: … application/fhir+json". Before the shared lookup
/// (2026-09-22), the load-and-404 step was written at 17 sites in 7 files
/// with four wordings.
///
/// The route list is read from the registrations, as in
/// every_route_is_guarded_test.dart. PUT is left out: an absent id there
/// is a create.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String adminToken;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    adminToken = await issueTestToken(
      db,
      username: 'absent-admin',
      role: 'admin',
      scopes: ['system/*.*'],
    );
  });

  tearDown(() => db.close());

  /// Query that carries a GET past its own parameter checks to the load.
  const query = <String, String>{
    r'/CodeSystem/<id>/$validate-code': '?code=x',
    r'/ValueSet/<id>/$validate-code': '?code=x',
    r'/CodeSystem/<id>/$lookup': '?code=x',
    r'/ConceptMap/<id>/$translate': '?code=x&system=s',
    r'/CodeSystem/<id>/$subsumes': '?codeA=a&codeB=b',
  };
  const parameters = '{"resourceType":"Parameters","parameter":['
      '{"name":"code","valueCode":"x"},{"name":"system","valueUri":"s"},'
      '{"name":"codeA","valueCode":"a"},{"name":"codeB","valueCode":"b"},'
      '{"name":"meta","valueMeta":{"tag":[{"code":"x"}]}}]}';

  test('every route that names a resource answers an absent id alike',
      () async {
    final source = File('lib/src/fhirant_server.dart').readAsStringSync();
    final routes = RegExp(
      r"\.\.(get|post|put|delete|patch|all|head)\(\s*r?'([^']+)'",
      dotAll: true,
    )
        .allMatches(source)
        .map((m) => (verb: m.group(1)!.toUpperCase(), path: m.group(2)!))
        .where(
          (r) =>
              (r.path.contains('<id>') || r.path.contains('<compartmentId>')) &&
              r.verb != 'PUT',
        )
        .toList();
    expect(routes, hasLength(24));

    final unalike = <String>[];
    for (final route in routes) {
      final verb = route.verb == 'ALL' ? 'GET' : route.verb;
      final url = route.path
              .replaceAll('<compartmentType>', 'Patient')
              .replaceAll('<compartmentId>', 'absent-id')
              .replaceAll('<resourceType>', 'Patient')
              .replaceAll('<vid>', '1')
              .replaceAll('<id>', 'absent-id') +
          (verb == 'GET' ? (query[route.path] ?? '') : '');
      final isPatch = verb == 'PATCH';
      final response = await handler(
        testRequest(
          verb,
          url,
          authToken: adminToken,
          headers: {
            'content-type': isPatch
                ? 'application/json-patch+json'
                : 'application/fhir+json',
          },
          body: verb == 'GET' || verb == 'DELETE'
              ? null
              : isPatch
                  ? '[{"op":"add","path":"/active","value":true}]'
                  : parameters,
        ),
      );
      final body = await response.readAsString();
      Object? decoded;
      try {
        decoded = jsonDecode(body);
      } on FormatException {
        decoded = null;
      }
      Object? code;
      if (decoded is Map) {
        final issues = decoded['issue'];
        if (issues is List && issues.isNotEmpty && issues.first is Map) {
          code = (issues.first as Map)['code'];
        }
      }
      final label = response.headers['content-type'] ?? 'none';
      if (response.statusCode != 404 ||
          !label.startsWith('application/fhir+json') ||
          code != 'not-found') {
        unalike.add(
          '$verb ${route.path} -> ${response.statusCode} $label code=$code',
        );
      }
    }
    expect(unalike, isEmpty);
  });
}
