import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// SMART App Launch STU 2.2 (hl7.org/fhir/smart-app-launch/STU2.2/
/// app-launch.html, read 2026-10-18), "Refresh access token", response:
/// "expires_in required The lifetime in seconds of the access token." The
/// access token response: "expires_in recommended Lifetime in seconds of the
/// access token, after which the token SHALL NOT be accepted by the resource
/// server". REVIEW-2026-10-17 (smaller list): neither reply carried it.
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

  Map<String, dynamic> claims(String token) {
    final part = token.split('.')[1];
    final json = utf8.decode(base64Url.decode(base64Url.normalize(part)));
    return jsonDecode(json) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> token(String body, String contentType) async {
    final r = await handler(
      testRequest(
        'POST',
        '/auth/token',
        body: body,
        headers: {'content-type': contentType},
      ),
    );
    final text = await r.readAsString();
    expect(r.statusCode, 200, reason: text);
    return jsonDecode(text) as Map<String, dynamic>;
  }

  /// [reply]'s expires_in is the lifetime of the access token it carries.
  void expectLifetimeOf(Map<String, dynamic> reply) {
    expect(reply['expires_in'], isA<int>(), reason: '$reply');
    final access = claims(reply['access_token'] as String);
    final lifetime = (access['exp'] as int) - (access['iat'] as int);
    expect(reply['expires_in'], lifetime);
  }

  test('the authorization code exchange carries expires_in', () async {
    await db.createAuthorizationCode(
      code: 'c1',
      clientId: 'app',
      userId: userId,
      redirectUri: 'http://localhost/cb',
      scope: 'user/*.rs',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
    final reply = await token(
      jsonEncode({
        'grant_type': 'authorization_code',
        'code': 'c1',
        'redirect_uri': 'http://localhost/cb',
        'client_id': 'app',
      }),
      'application/json',
    );
    expectLifetimeOf(reply);
    expect(reply['expires_in'], const Duration(hours: 8).inSeconds);
  });

  test('the refresh reply carries expires_in', () async {
    final refresh = JwtService(testJwtSecret).generateRefreshToken(
      userId: userId,
      username: 'nurse',
      role: 'clinician',
      scopes: ['user/*.rs'],
    );
    final reply = await token(
      'grant_type=refresh_token&refresh_token=$refresh',
      'application/x-www-form-urlencoded',
    );
    expectLifetimeOf(reply);
  });

  test('near the session end, expires_in is the shortened lifetime', () async {
    // A refresh caps the new access token at the session's end
    // (refresh_keeps_session_end_test); expires_in says so.
    final refresh = JwtService(
      testJwtSecret,
      refreshTokenLifetime: const Duration(hours: 1),
    ).generateRefreshToken(
      userId: userId,
      username: 'nurse',
      role: 'clinician',
      scopes: ['user/*.rs'],
    );
    final reply = await token(
      'grant_type=refresh_token&refresh_token=$refresh',
      'application/x-www-form-urlencoded',
    );
    expectLifetimeOf(reply);
    expect(reply['expires_in'], lessThanOrEqualTo(3600));
  });
}
