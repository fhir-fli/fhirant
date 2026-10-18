import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// OWASP ASVS 5.0.0 V10.4.8 (L2, release JSON, read 2026-10-17, verbatim):
/// "Verify that refresh tokens have an absolute expiration, including if
/// sliding refresh token expiration is applied." REVIEW-2026-10-17 finding
/// 17, measured over HTTP: each rotation issued a refresh token with a fresh
/// 7 days, so a session refreshed within every 7 days never ended. A rotated
/// token now keeps the expiry of the one it replaces, and no token a
/// refresh issues outlives it.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late int userId;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    await issueTestToken(db, username: 'nurse', scopes: ['user/*.rs']);
    userId = (await db.getUserByUsername('nurse'))!.id;
  });

  tearDown(() => db.close());

  int expOf(String token) {
    final part = token.split('.')[1];
    final json = utf8.decode(base64Url.decode(base64Url.normalize(part)));
    return (jsonDecode(json) as Map<String, dynamic>)['exp'] as int;
  }

  Future<Map<String, dynamic>> refresh(String token) async {
    final r = await handler(
      testRequest(
        'POST',
        '/auth/token',
        body: 'grant_type=refresh_token&refresh_token=$token',
        headers: {'content-type': 'application/x-www-form-urlencoded'},
      ),
    );
    final body = await r.readAsString();
    expect(r.statusCode, 200, reason: body);
    return jsonDecode(body) as Map<String, dynamic>;
  }

  String refreshToken({Duration life = const Duration(days: 7)}) =>
      JwtService(testJwtSecret, refreshTokenLifetime: life)
          .generateRefreshToken(
        userId: userId,
        username: 'nurse',
        role: 'clinician',
        scopes: ['user/*.rs'],
      );

  test('a rotated refresh token keeps the original expiry', () async {
    final first = refreshToken();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final second = (await refresh(first))['refresh_token'] as String;
    expect(expOf(second), expOf(first));
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final third = (await refresh(second))['refresh_token'] as String;
    expect(expOf(third), expOf(first));
  });

  test('an access token from a refresh does not outlive the session', () async {
    final short = refreshToken(life: const Duration(hours: 1));
    final answer = await refresh(short);
    expect(
      expOf(answer['access_token'] as String),
      lessThanOrEqualTo(
        expOf(short),
      ),
    );
  });
}
