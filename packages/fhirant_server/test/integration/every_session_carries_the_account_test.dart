@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:fhirant_server/src/utils/smart_scopes.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// Every route that mints a session mints it from the account row: the
/// access and refresh tokens carry the account's current token generation
/// and the scopes it holds.
///
/// The generation is what ends earlier sessions after a password, role,
/// scope or activation change (auth/token_bound.dart; REVIEW-2026-09-17
/// A14). A token minted without it counts as generation 0 and dies at the
/// first such change. Before the shared minter (2026-09-22) the pair was
/// minted at five sites; registration's carried no generation, which was
/// harmless only because a new account is at generation 0. Four routes
/// mint: register, login, the refresh grant, and the caller's password
/// change.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String adminToken;
  final jwt = JwtService(testJwtSecret);

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    adminToken = await issueTestToken(
      db,
      username: 'admin-one',
      role: 'admin',
      scopes: ['system/*.*'],
    );
  });

  tearDown(() => db.close());

  Future<(int, Map<String, dynamic>)> send(
    String method,
    String path, {
    String? token,
    Object? body,
  }) async {
    final r = await handler(
      testRequest(
        method,
        path,
        authToken: token,
        headers: {if (body != null) 'content-type': 'application/json'},
        body: body == null ? null : jsonEncode(body),
      ),
    );
    final text = await r.readAsString();
    return (r.statusCode, jsonDecode(text) as Map<String, dynamic>);
  }

  /// Checks that both tokens of [reply] carry the account's row.
  Future<void> carriesTheAccount(
    String route,
    Map<String, dynamic> reply,
    int userId,
  ) async {
    final user = (await db.getUserById(userId))!;
    final held = SmartScopeEnforcer.heldScopes(user).join(' ');
    for (final key in ['access_token', 'token', 'refresh_token']) {
      final token = reply[key];
      if (token is! String) continue;
      final payload = jwt.verifyToken(token) ??
          jwt.verifyRefreshToken(token) ??
          (throw StateError('$route: $key does not verify'));
      expect(payload['gen'], user.tokenGeneration, reason: '$route $key gen');
      expect(payload['userId'], user.id, reason: '$route $key userId');
      expect(payload['scope'], held, reason: '$route $key scope');
    }
  }

  test('register, login, refresh and password change all mint from the row',
      () async {
    const password = 'bob-password-1';
    final (s0, registered) = await send(
      'POST',
      '/auth/register',
      token: adminToken,
      body: {'username': 'bob-user', 'password': password, 'role': 'clinician'},
    );
    expect(s0, 201, reason: '$registered');
    final bobId = registered['id'] as int;
    await carriesTheAccount('register', registered, bobId);

    // A role change moves the generation on (A14), so from here every
    // session must carry 1, not the 0 a request-built token would.
    final (s1, _) = await send(
      'PUT',
      '/admin/users/$bobId/role',
      token: adminToken,
      body: {'role': 'readonly'},
    );
    expect(s1, 200);
    expect((await db.getUserById(bobId))!.tokenGeneration, 1);

    final (s2, loggedIn) = await send(
      'POST',
      '/auth/login',
      body: {'username': 'bob-user', 'password': password},
    );
    expect(s2, 200, reason: '$loggedIn');
    await carriesTheAccount('login', loggedIn, bobId);

    final (s3, refreshed) = await send(
      'POST',
      '/auth/token',
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': loggedIn['refresh_token'],
      },
    );
    expect(s3, 200, reason: '$refreshed');
    await carriesTheAccount('refresh', refreshed, bobId);

    final (s4, changed) = await send(
      'POST',
      '/auth/password',
      token: refreshed['access_token'] as String,
      body: {'current_password': password, 'new_password': 'bob-password-2'},
    );
    expect(s4, 200, reason: '$changed');
    expect((await db.getUserById(bobId))!.tokenGeneration, 2);
    await carriesTheAccount('password change', changed, bobId);
  });
}
