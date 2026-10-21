import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// RFC 9700 4.14.2 (read 2026-09-19, verbatim), refresh token rotation: "If
/// a refresh token is compromised and subsequently used by both the
/// attacker and the legitimate client, one of them will present an
/// invalidated refresh token, which will inform the authorization server of
/// the breach." OWASP ASVS 5.0.0 V15.4.2 (read 2026-10-21): the check on a
/// resource's state and the action that depends on it "are performed as a
/// single atomic operation". The revoked check and the revoke were two
/// statements with the session issued between them, so ten uses of one
/// refresh token at once all got tokens (concurrency_probe, 5 of 5; one at
/// a time, the second was 401).
void main() {
  late FhirAntDb db;
  late Handler handler;

  setUp(() async {
    final server = await createTestServer(authMaxRequests: 1000);
    db = server.db;
    handler = server.handler;
    final admin = await issueTestToken(
      db,
      username: 'adm',
      role: 'admin',
      scopes: ['system/*.*'],
    );
    final r = await handler(
      testRequest(
        'POST',
        '/auth/register',
        authToken: admin,
        body: jsonEncode({
          'username': 'ref',
          'password': 'a-long-enough-password-123',
        }),
      ),
    );
    expect(r.statusCode, 201, reason: await r.readAsString());
  });

  tearDown(() => db.close());

  Future<String> loginRefreshToken() async {
    final r = await handler(
      testRequest(
        'POST',
        '/auth/login',
        body: jsonEncode({
          'username': 'ref',
          'password': 'a-long-enough-password-123',
        }),
      ),
    );
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    return body['refresh_token'] as String;
  }

  Future<Response> refresh(String token) async => handler(
        testRequest(
          'POST',
          '/auth/token',
          body: 'grant_type=refresh_token&refresh_token=$token',
          headers: {'content-type': 'application/x-www-form-urlencoded'},
        ),
      );

  test('ten uses of one refresh token at once: exactly one gets tokens',
      () async {
    final token = await loginRefreshToken();
    final rs = await Future.wait([for (var i = 0; i < 10; i++) refresh(token)]);
    final statuses = rs.map((r) => r.statusCode).toList()..sort();
    expect(statuses, [200, for (var i = 0; i < 9; i++) 401]);
  });

  test('the reuse ends the session the winning use was given', () async {
    final token = await loginRefreshToken();
    final rs = await Future.wait([refresh(token), refresh(token)]);
    final winner = rs.firstWhere((r) => r.statusCode == 200);
    final body =
        jsonDecode(await winner.readAsString()) as Map<String, dynamic>;
    final next = await refresh(body['refresh_token'] as String);
    expect(next.statusCode, 401, reason: await next.readAsString());
  });
}
