// Real Argon2id hashes on every login.
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-17 A16. RFC 6749 §5.1 (verbatim): "The authorization
/// server MUST include the HTTP "Cache-Control" response header field
/// [RFC2616] with a value of "no-store" in any response containing tokens,
/// credentials, or other sensitive information, as well as the "Pragma"
/// response header field [RFC2616] with a value of "no-cache"."
void main() {
  late FhirAntDb db;
  late Handler handler;
  late Directory exportDir;
  const password = 'Cache-Password-1';

  setUp(() async {
    exportDir = await Directory.systemTemp.createTemp('nostore');
    final server = await createTestServer(exportDir: exportDir.path);
    db = server.db;
    handler = server.handler;
  });

  tearDown(() async {
    await db.close();
    await exportDir.delete(recursive: true);
  });

  Future<void> createUser(String name) async {
    final salt = PasswordHasher.generateSalt();
    await db.createUser(
      username: name,
      passwordHash: await PasswordHasher.hashPassword(password, salt),
      salt: salt,
    );
  }

  Future<Response> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async =>
      handler(
        testRequest(
          'POST',
          path,
          authToken: token,
          headers: {'content-type': 'application/json'},
          body: jsonEncode(body),
        ),
      );

  void expectNoStore(Response r) {
    expect(r.headers['cache-control'], 'no-store');
    expect(r.headers['pragma'], 'no-cache');
  }

  test('the first registration (tokens in the body)', () async {
    final r = await post(
      '/auth/register',
      {'username': 'first-admin', 'password': password},
    );
    expect(r.statusCode, 201);
    expectNoStore(r);
  });

  test('login', () async {
    await createUser('cache-user');
    final r = await post(
      '/auth/login',
      {'username': 'cache-user', 'password': password},
    );
    expect(r.statusCode, 200);
    expectNoStore(r);
  });

  test('the refresh grant', () async {
    await createUser('cache-user');
    final login = await post(
      '/auth/login',
      {'username': 'cache-user', 'password': password},
    );
    final refresh =
        (jsonDecode(await login.readAsString()) as Map)['refresh_token'];
    final r = await post(
      '/auth/token',
      {'grant_type': 'refresh_token', 'refresh_token': refresh},
    );
    expect(r.statusCode, 200);
    expectNoStore(r);
  });

  test('the authorization code grant and the JSON authorize response',
      () async {
    await createUser('cache-user');
    final userId = (await db.getUserByUsername('cache-user'))!.id;
    await db.createAuthorizationCode(
      code: 'cache-code',
      clientId: 'app',
      userId: userId,
      redirectUri: 'http://localhost/cb',
      scope: 'user/*.rs',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
    final r = await post('/auth/token', {
      'grant_type': 'authorization_code',
      'code': 'cache-code',
      'redirect_uri': 'http://localhost/cb',
      'client_id': 'app',
    });
    expect(r.statusCode, 200);
    expectNoStore(r);
  });

  // RFC 7636 appendix B's pair, verbatim.
  const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
  const challenge = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';
  const authorize = {
    'response_type': 'code',
    'client_id': 'app',
    'redirect_uri': 'http://localhost/cb',
    'scope': 'user/*.rs',
    'state': 'xyz',
    'code_challenge': challenge,
    'code_challenge_method': 'S256',
    'aud': 'http://localhost:8080',
    'username': 'cache-user',
    'password': password,
  };

  test('the JSON authorize response (the code in the body)', () async {
    await createUser('cache-user');
    final r = await post('/auth/authorize', authorize);
    expect(r.statusCode, 200, reason: await r.readAsString());
    expectNoStore(r);
  });

  test('the form authorize redirect (the code in Location)', () async {
    await createUser('cache-user');
    final r = await handler(
      testRequest(
        'POST',
        '/auth/authorize',
        headers: {'content-type': 'application/x-www-form-urlencoded'},
        body: Uri(queryParameters: authorize).query,
      ),
    );
    expect(r.statusCode, 302, reason: await r.readAsString());
    expect(r.headers['location'], contains('code='));
    expectNoStore(r);
    // The verifier is what the challenge came from; the code exchanges.
    final code = Uri.parse(r.headers['location']!).queryParameters['code'];
    final t = await post('/auth/token', {
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': 'http://localhost/cb',
      'client_id': 'app',
      'code_verifier': verifier,
    });
    expect(t.statusCode, 200, reason: await t.readAsString());
  });

  test('a password change (a fresh token pair)', () async {
    await createUser('cache-user');
    final login = await post(
      '/auth/login',
      {'username': 'cache-user', 'password': password},
    );
    final token = (jsonDecode(await login.readAsString()) as Map)['token'];
    final r = await post(
      '/auth/password',
      {'current_password': password, 'new_password': 'Cache-Password-2'},
      token: token as String,
    );
    expect(r.statusCode, 200);
    expectNoStore(r);
  });
}
