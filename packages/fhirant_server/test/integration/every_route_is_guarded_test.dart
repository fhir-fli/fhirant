// Real Argon2id hashes when a token is minted.
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// Every route the server registers is knocked on twice: once with no
/// credential, once with a token whose scopes cover nothing it asks for.
/// Neither may be answered.
///
/// Why the list is read from the source rather than written here: the three
/// authorization gaps in REVIEW-2026-09-17 (A5 HEAD, A6 SearchParameter
/// delete, A7 PATCH) were each one route that had forgotten to check, and
/// they were missed because verification meant reading the handlers there
/// was a reason to open. A hand-written list of routes has the same hole:
/// it can only hold the routes someone remembered. This one cannot be
/// partial, because it is the registrations themselves.
///
/// OWASP Authorization Cheat Sheet, "Validate the Permissions on Every
/// Request" (raw markdown read 2026-09-21, verbatim): "Even if just a
/// single access control check is "missed", the confidentiality and/or
/// integrity of a resource can be jeopardized. Validating permissions
/// correctly on just the majority of requests is insufficient."
void main() {
  /// The routes, read from `createRouter`'s own registrations.
  ///
  /// Both quotings are matched: `'/metadata'` and `r'/$backup'`. A pattern
  /// without the `r?` found 38 of the 89 and silently dropped every
  /// operation.
  List<({String verb, String path})> registeredRoutes() {
    final source = File('lib/src/fhirant_server.dart').readAsStringSync();
    final pattern = RegExp(
      r"\.\.(get|post|put|delete|patch|all|head|mount|add)\(\s*r?'([^']+)'",
      dotAll: true,
    );
    return [
      for (final m in pattern.allMatches(source))
        (verb: m.group(1)!.toUpperCase(), path: m.group(2)!),
    ];
  }

  /// The routes that take no credential by design: the welcome page, the
  /// capability statement, the health check, the favicon, SMART discovery
  /// and everything under `auth/` (a caller without a token is exactly who
  /// uses those).
  bool isPublic(String path) =>
      path == '/' ||
      path == '/favicon.ico' ||
      path == '/health' ||
      path == '/metadata' ||
      path == '/.well-known/smart-configuration' ||
      path.startsWith('/auth/') ||
      path == '/ws';

  /// A concrete URL for a route pattern.
  String concrete(String path) => path
      .replaceAll('<resourceType>', 'Patient')
      .replaceAll('<compartmentType>', 'Patient')
      .replaceAll('<compartmentId>', 'p1')
      .replaceAll('<groupId>', 'g1')
      .replaceAll('<userId>', '1')
      .replaceAll('<jobId>', 'j1')
      .replaceAll('<fileName>', 'f.ndjson')
      .replaceAll('<vid>', '1')
      .replaceAll('<id>', 'p1');

  late FhirAntDb db;
  late Handler handler;
  late Directory exportDir;
  late String wrongScopeToken;

  setUp(() async {
    exportDir = await Directory.systemTemp.createTemp('routes');
    final server = await createTestServer(exportDir: exportDir.path);
    db = server.db;
    handler = server.handler;
    // A real account, whose scopes name a type none of these routes serve.
    wrongScopeToken = await issueTestToken(
      db,
      username: 'narrow-user',
      scopes: ['user/Practitioner.rs'],
    );
  });

  tearDown(() async {
    await db.close();
    await exportDir.delete(recursive: true);
  });

  test('the route list comes from the source and is not empty', () {
    final routes = registeredRoutes();
    expect(routes.length, greaterThan(80), reason: 'the parse found few');
    expect(
      routes.where((r) => r.path.contains(r'$')).length,
      greaterThan(40),
      reason: 'operations are registered as raw strings',
    );
  });

  test('no route answers without a credential', () async {
    final refused = <String>[];
    final answered = <String>[];
    for (final route in registeredRoutes()) {
      if (isPublic(route.path)) continue;
      final verb = route.verb == 'ALL' ? 'GET' : route.verb;
      final response = await handler(
        testRequest(verb, concrete(route.path)),
      );
      final line = '$verb ${route.path} -> ${response.statusCode}';
      (response.statusCode == 401 ? refused : answered).add(line);
    }
    expect(answered, isEmpty, reason: 'answered without a token');
    expect(refused.length, greaterThan(60));
  });

  test('no route answers a token whose scopes cover nothing it serves',
      () async {
    final answered = <String>[];
    for (final route in registeredRoutes()) {
      if (isPublic(route.path)) continue;
      final verb = route.verb == 'ALL' ? 'GET' : route.verb;
      final response = await handler(
        testRequest(verb, concrete(route.path), authToken: wrongScopeToken),
      );
      // Returning DATA is the failure. A refusal (403, 404, 400, 422,
      // 405) is fine, and so is an empty answer: `POST /_search` searches
      // the types the caller may read, which here is none, so it answers
      // an empty searchset rather than refusing. Measured 2026-09-21:
      // `total: 0`, no entries, with a Patient stored.
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = await response.readAsString();
        final hasEntries = body.contains('"entry"');
        final total = RegExp(r'"total":\s*(\d+)').firstMatch(body);
        final empty = !hasEntries && (total == null || total.group(1) == '0');
        if (!empty) {
          answered.add('$verb ${route.path} -> ${response.statusCode}');
        }
      }
    }
    expect(answered, isEmpty, reason: 'answered a token with no scope for it');
  });
}
