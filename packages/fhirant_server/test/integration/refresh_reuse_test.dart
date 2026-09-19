// Real Argon2id hash on the login.
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';
import 'package:fhirant_server/src/utils/token_hasher.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-17 A16: refresh rotation had no reuse detection. RFC
/// 9700 §4.14.2 (verbatim): "The authorization server cannot determine
/// which party submitted the invalid refresh token, but it will revoke the
/// active refresh token. This stops the attack at the cost of forcing the
/// legitimate client to obtain a fresh authorization grant."
void main() {
  late FhirAntDb db;
  late Handler handler;
  late Directory exportDir;
  const password = 'Reuse-Password-1';

  setUp(() async {
    exportDir = await Directory.systemTemp.createTemp('reuse');
    final server = await createTestServer(exportDir: exportDir.path);
    db = server.db;
    handler = server.handler;
    final salt = PasswordHasher.generateSalt();
    await db.createUser(
      username: 'reuse-user',
      passwordHash: await PasswordHasher.hashPassword(password, salt),
      salt: salt,
    );
  });

  tearDown(() async {
    await db.close();
    await exportDir.delete(recursive: true);
  });

  Future<(int, Map<String, dynamic>)> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final r = await handler(
      testRequest(
        'POST',
        path,
        headers: {'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
    return (
      r.statusCode,
      jsonDecode(await r.readAsString()) as Map<String, dynamic>,
    );
  }

  Future<(int, Map<String, dynamic>)> refresh(String token) => post(
        '/auth/token',
        {'grant_type': 'refresh_token', 'refresh_token': token},
      );

  Future<int> read(String token) async =>
      (await handler(testRequest('GET', '/Patient', authToken: token)))
          .statusCode;

  test('a rotated-away refresh token presented again ends the whole grant',
      () async {
    final (_, login) = await post(
      '/auth/login',
      {'username': 'reuse-user', 'password': password},
    );
    final first = login['refresh_token'] as String;

    final (s1, rotated) = await refresh(first);
    expect(s1, 200, reason: '$rotated');
    final second = rotated['refresh_token'] as String;
    final access = rotated['access_token'] as String;
    expect(await read(access), 200);

    // The attacker (or the client) presents the token that was rotated
    // away.
    final (s2, reuse) = await refresh(first);
    expect(s2, 401);
    expect(reuse['error'], 'invalid_grant');

    // Both parties lose: the active refresh token and the access token
    // issued with it are over.
    final (s3, _) = await refresh(second);
    expect(s3, 401, reason: 'the active refresh token is revoked too');
    expect(await read(access), 401);

    // A fresh login is the way back.
    final (s4, _) = await post(
      '/auth/login',
      {'username': 'reuse-user', 'password': password},
    );
    expect(s4, 200);
  });

  test(
      'a forged token that happens to be in the revoked table cannot end '
      'a grant: the signature is checked first', () async {
    final (_, login) = await post(
      '/auth/login',
      {'username': 'reuse-user', 'password': password},
    );
    final refreshToken = login['refresh_token'] as String;
    final access = login['token'] as String;
    // A token with a bad signature, revoked by hash as if by a logout.
    final forged = '${refreshToken.substring(0, refreshToken.length - 2)}xx';
    await db.revokeToken(
      TokenHasher.hash(forged),
      DateTime.now().add(const Duration(days: 1)),
    );
    final (s, _) = await refresh(forged);
    expect(s, 401);
    expect(await read(access), 200, reason: 'the grant stands');
  });
}
