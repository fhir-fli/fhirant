@Timeout(Duration(minutes: 6))
library;

import 'dart:io';

import 'package:test/test.dart';

import 'test_helpers.dart';

/// Every door the server opens is behind the rate limiter, including doors
/// nothing registers.
///
/// A flood costs the phone battery and the store's IO whatever the path, so
/// a route that is not counted is a way to spend both without a credential.
/// The limiter runs before authentication for that reason
/// (REVIEW-2026-09-06 finding 11).
///
/// Each route gets its OWN server: at handler level every request shares one
/// rate-limit bucket (`_trustedClientIpMiddleware` writes `unknown` when
/// there is no socket), so one server per route is what keeps the count
/// honest.
///
/// The route list is read from the registrations, as in
/// every_route_is_guarded_test.dart, and this test also sends requests that
/// match NO registration: a list-driven check only covers its list.
void main() {
  const limit = 3;

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

  String concrete(String path) => path
      .replaceAll('<resourceType>', 'Patient')
      .replaceAll('<compartmentType>', 'Patient')
      .replaceAll('<compartmentId>', 'p1')
      .replaceAll('<groupId>', 'g1')
      .replaceAll('<userId>', '2')
      .replaceAll('<jobId>', 'j1')
      .replaceAll('<fileName>', 'f.ndjson')
      .replaceAll('<vid>', '1')
      .replaceAll('<id>', 'p1');

  /// The statuses of [limit] + 1 requests to [verb] [path], on a server of
  /// their own. No credential: the limiter runs before authentication, so a
  /// 401 still counts as a request that was let through.
  Future<List<int>> floodOneRoute(String verb, String path) async {
    final server = await createTestServer(maxRequests: limit);
    final statuses = <int>[];
    for (var i = 0; i < limit + 1; i++) {
      final response = await server.handler(testRequest(verb, path));
      statuses.add(response.statusCode);
    }
    await server.db.close();
    return statuses;
  }

  test('the route list is the whole list', () {
    final routes = registeredRoutes();
    // The census of 2026-09-21: 89 registrations, 51 of them operations
    // (paths holding a `$`). A pattern that silently stops matching — the
    // first one missed every raw-string route, 38 of the 89 — fails here
    // rather than passing a shrunken list to the tests below.
    expect(routes, hasLength(89));
    expect(
      routes.where((r) => r.path.contains(r'$')),
      hasLength(51),
    );
    expect(
      routes.map((r) => '${r.verb} ${r.path}'),
      containsAll(<String>[
        'GET /metadata',
        r'POST /$reindex',
        'DELETE /<resourceType>/<id>',
      ]),
    );
  });

  test('every registered route is rate limited', () async {
    final unlimited = <String>[];
    for (final route in registeredRoutes()) {
      final verb = route.verb == 'ALL' ? 'GET' : route.verb;
      final statuses = await floodOneRoute(verb, concrete(route.path));
      if (statuses.last != 429) {
        unlimited.add('$verb ${route.path} -> $statuses');
      }
    }
    expect(unlimited, isEmpty);
  });

  test('a path no route matches is rate limited', () async {
    final statuses = await floodOneRoute('GET', '/not-a-route');
    expect(statuses.last, 429);
  });

  test('a method no route registers is rate limited', () async {
    final statuses = await floodOneRoute('TRACE', '/Patient');
    expect(statuses.last, 429);
  });

  test('the credential endpoints have their own, tighter bucket', () async {
    final server = await createTestServer(
      maxRequests: 50,
      authMaxRequests: 2,
    );
    Future<int> login() async => (await server.handler(
          testRequest(
            'POST',
            '/auth/login',
            headers: {'content-type': 'application/json'},
            body: '{"username":"nobody","password":"wrong"}',
          ),
        ))
            .statusCode;
    final statuses = <int>[for (var i = 0; i < 4; i++) await login()];
    await server.db.close();
    expect(statuses.last, 429, reason: 'got $statuses');
    // Control: a route on the general bucket is still answering, so the 429
    // above came from the credential bucket and not from the general one.
    final other = await server.handler(testRequest('GET', '/health'));
    expect(other.statusCode, isNot(429));
  });
}
