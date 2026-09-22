@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// A body that is not JSON is the client's mistake, and every route that
/// reads one answers 4xx, never 5xx.
///
/// RFC 9110 §15.5.1, read 2026-09-22, verbatim: "The 400 (Bad Request)
/// status code indicates that the server cannot or will not process the
/// request due to something that is perceived to be a client error (e.g.,
/// malformed request syntax…)". §15.6.1: 500 "indicates that the server
/// encountered an unexpected condition that prevented it from fulfilling
/// the request."
///
/// Two handlers (create, patch) used to answer a STORE failure as 400
/// (PR #3); this is the mirror: a handler whose one catch covers parsing
/// the body answers a garbled body as 500 "Internal error", and the client
/// is told the server is broken. The route list is read from the
/// registrations, as in every_route_is_guarded_test.dart.
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
      username: 'garble-admin',
      role: 'admin',
      scopes: ['system/*.*'],
    );
  });

  tearDown(() => db.close());

  test('every route that reads a body answers a garbled body with 4xx',
      () async {
    final source = File('lib/src/fhirant_server.dart').readAsStringSync();
    final routes = RegExp(
      r"\.\.(get|post|put|delete|patch|all|head|mount|add)\(\s*r?'([^']+)'",
      dotAll: true,
    ).allMatches(source).map(
          (m) => (verb: m.group(1)!.toUpperCase(), path: m.group(2)!),
        );
    final serverFault = <String>[];
    var tried = 0;
    for (final route in routes) {
      final verb = route.verb == 'ALL' ? 'POST' : route.verb;
      if (verb == 'GET' || verb == 'DELETE' || verb == 'HEAD') continue;
      if (route.path == '/ws') continue;
      final url = route.path
          .replaceAll('<resourceType>', 'Patient')
          .replaceAll('<compartmentType>', 'Patient')
          .replaceAll('<compartmentId>', 'nope')
          .replaceAll('<groupId>', 'nope')
          .replaceAll('<jobId>', 'nope')
          .replaceAll('<fileName>', 'nope.ndjson')
          .replaceAll('<userId>', '99')
          .replaceAll('<vid>', '999')
          .replaceAll('<id>', 'nope');
      for (final contentType in ['application/fhir+json', 'application/json']) {
        tried++;
        final response = await handler(
          testRequest(
            verb,
            url,
            authToken: adminToken,
            headers: {'content-type': contentType},
            body: '{this is not json',
          ),
        );
        if (response.statusCode >= 500) {
          serverFault.add(
            '$verb ${route.path} ($contentType) -> ${response.statusCode}',
          );
        }
      }
    }
    expect(serverFault, isEmpty);
    // Control: the loop sent something.
    expect(tried, greaterThan(40));
  });
}
