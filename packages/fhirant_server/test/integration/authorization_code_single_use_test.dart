import 'dart:convert';
import 'dart:io';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-17 A16: the authorization code's `used` check and its
/// mark were two statements, so two exchanges arriving together both got
/// tokens. RFC 6749 §4.1.2 (verbatim): "If an authorization code is used
/// more than once, the authorization server MUST deny the request and
/// SHOULD revoke (when possible) all tokens previously issued based on
/// that authorization code."
void main() {
  late FhirAntDb db;
  late Handler handler;
  late Directory exportDir;
  late int userId;

  setUp(() async {
    exportDir = await Directory.systemTemp.createTemp('authcode');
    final server = await createTestServer(exportDir: exportDir.path);
    db = server.db;
    handler = server.handler;
    await issueTestToken(db, username: 'code-user', scopes: ['user/*.rs']);
    userId = (await db.getUserByUsername('code-user'))!.id;
  });

  tearDown(() async {
    await db.close();
    await exportDir.delete(recursive: true);
  });

  Future<void> storeCode(String code) => db.createAuthorizationCode(
        code: code,
        clientId: 'app',
        userId: userId,
        redirectUri: 'http://localhost/cb',
        scope: 'user/*.rs',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );

  Future<(int, Map<String, dynamic>)> exchange(String code) async {
    final r = await handler(
      testRequest(
        'POST',
        '/auth/token',
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': 'http://localhost/cb',
          'client_id': 'app',
        }),
      ),
    );
    return (
      r.statusCode,
      jsonDecode(await r.readAsString()) as Map<String, dynamic>,
    );
  }

  Future<int> read(String token) async =>
      (await handler(testRequest('GET', '/Patient', authToken: token)))
          .statusCode;

  test('two exchanges of one code at once: exactly one gets tokens', () async {
    await storeCode('race-code');
    final results = await Future.wait([
      exchange('race-code'),
      exchange('race-code'),
    ]);
    final statuses = results.map((r) => r.$1).toList()..sort();
    expect(statuses, [200, 400], reason: '$results');
  });

  test('a second use is denied and ends the tokens from the first', () async {
    await storeCode('once-code');
    final (s1, first) = await exchange('once-code');
    expect(s1, 200, reason: '$first');
    final access = first['access_token'] as String;
    expect(await read(access), 200);

    final (s2, second) = await exchange('once-code');
    expect(s2, 400);
    expect(second['error'], 'invalid_grant');
    expect(await read(access), 401, reason: 'revoked on reuse');
  });
}
