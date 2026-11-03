// Real password hashes (Argon2id) on every login; past the 30 s default
// under the whole suite.
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/auth/one_time_password.dart';
import 'package:fhirant_server/src/utils/password_policy.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// OWASP ASVS 5.0.0 V6.4.1 (L1) and V6.4.6 (L3), asvs 5.0.0 JSON, verbatim:
/// "system generated initial passwords or activation codes are securely
/// randomly generated, follow the existing password policy, and expire after
/// a short period of time or after they are initially used. These initial
/// secrets must not be permitted to become the long term password", and
/// "administrative users can initiate the password reset process for the
/// user, but that this does not allow them to change or choose the user's
/// password".
///
/// An administrator chose the password of every account it created and
/// every password it reset, and the user kept it. Now the server makes a
/// one-time password, the administrator reads it once and hands it over,
/// and it does one thing: set the user's own password, within
/// [oneTimePasswordLifetime].
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String adminToken;
  late Directory exportDir;

  setUp(() async {
    exportDir = await Directory.systemTemp.createTemp('one_time_password');
    final server = await createTestServer(exportDir: exportDir.path);
    db = server.db;
    handler = server.handler;
    adminToken = await issueTestToken(
      db,
      username: 'admin-one',
      role: 'admin',
      scopes: ['system/*.*'],
    );
  });

  tearDown(() async {
    await db.close();
    await exportDir.delete(recursive: true);
  });

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
    return (
      r.statusCode,
      text.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(text) as Map<String, dynamic>,
    );
  }

  Future<(int, Map<String, dynamic>)> login(String user, String password) =>
      send(
        'POST',
        '/auth/login',
        body: {'username': user, 'password': password},
      );

  Future<(int, Map<String, dynamic>)> setOwn(
    String user,
    String current,
    String next,
  ) =>
      send(
        'POST',
        '/auth/password',
        body: {
          'username': user,
          'current_password': current,
          'new_password': next,
        },
      );

  /// Creates `bob-user` as the administrator; returns its id and the
  /// one-time password.
  Future<(int, String)> createBob() async {
    final (status, body) = await send(
      'POST',
      '/auth/register',
      token: adminToken,
      body: {'username': 'bob-user'},
    );
    expect(status, 201, reason: '$body');
    return (body['id'] as int, body['one_time_password'] as String);
  }

  test('an administrator cannot choose a new account its password', () async {
    final (status, body) = await send(
      'POST',
      '/auth/register',
      token: adminToken,
      body: {'username': 'bob-user', 'password': 'bob-chosen-by-admin'},
    );
    expect(status, 400, reason: '$body');
    expect(await db.getUserByUsername('bob-user'), isNull);
  });

  test('a new account gets a one-time password and no session', () async {
    final (status, body) = await send(
      'POST',
      '/auth/register',
      token: adminToken,
      body: {'username': 'bob-user'},
    );
    expect(status, 201, reason: '$body');
    final once = body['one_time_password'];
    expect(once, isA<String>());
    expect(PasswordPolicy.validate(once as String), isNull);
    expect(body.containsKey('token'), isFalse, reason: 'no session for it');
    expect(body.containsKey('refresh_token'), isFalse);
    final expires = DateTime.parse(body['one_time_password_expires'] as String);
    final lifetime = expires.difference(DateTime.now());
    expect(lifetime, lessThanOrEqualTo(oneTimePasswordLifetime));
    expect(
      lifetime,
      greaterThan(oneTimePasswordLifetime - const Duration(minutes: 1)),
    );
  });

  test('two one-time passwords are not the same', () async {
    final (_, first) = await createBob();
    final (_, again) = await send(
      'POST',
      '/auth/register',
      token: adminToken,
      body: {'username': 'carol-user'},
    );
    expect(again['one_time_password'], isNot(first));
  });

  test('it opens no session, at login or at authorize', () async {
    final (_, once) = await createBob();
    final (status, body) = await login('bob-user', once);
    expect(status, 403, reason: '$body');
    expect(body['error'], 'password_change_required');
    expect(body.containsKey('token'), isFalse);

    final r = await handler(
      testRequest(
        'POST',
        '/auth/authorize',
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'response_type': 'code',
          'state': 'xyz',
          'aud': 'http://localhost:8080',
          'client_id': 'my-app',
          'redirect_uri': 'http://localhost:9999/cb',
          'code_challenge': 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
          'code_challenge_method': 'S256',
          'username': 'bob-user',
          'password': once,
        }),
      ),
    );
    final text = await r.readAsString();
    expect(r.statusCode, 403, reason: text);
    expect(text, isNot(contains('code=')));
    expect(r.headers['location'], isNull);
  });

  test('it sets the user its own password once, and is then spent', () async {
    final (_, once) = await createBob();
    final (status, body) = await setOwn('bob-user', once, 'bob-own-choice-1');
    expect(status, 200, reason: '$body');
    expect(body['token'], isA<String>(), reason: 'signed in as the change');

    expect((await login('bob-user', 'bob-own-choice-1')).$1, 200);
    expect((await login('bob-user', once)).$1, 401, reason: 'spent');
    expect((await setOwn('bob-user', once, 'bob-own-choice-2')).$1, 401);
  });

  test('the new password must meet the policy', () async {
    final (_, once) = await createBob();
    expect((await setOwn('bob-user', once, 'short')).$1, 400);
    expect(
      (await setOwn('bob-user', once, once)).$1,
      400,
      reason: 'the one-time password cannot become the long-term one',
    );
  });

  test('it expires, and an expired one answers as a wrong password', () async {
    final (id, once) = await createBob();
    await db.setPasswordTemporaryUntil(
      id,
      DateTime.now().subtract(const Duration(seconds: 1)),
    );
    final (wrongStatus, wrongBody) = await login('bob-user', 'not-the-one-1');
    final (status, body) = await login('bob-user', once);
    expect(status, wrongStatus);
    expect(body, wrongBody);
    expect((await setOwn('bob-user', once, 'bob-own-choice-1')).$1, 401);
  });

  test('a reset gives a one-time password; the administrator chooses none',
      () async {
    final (id, once) = await createBob();
    expect((await setOwn('bob-user', once, 'bob-own-choice-1')).$1, 200);
    final (_, session) = await login('bob-user', 'bob-own-choice-1');
    final bobToken = session['token'] as String;

    final (chosen, chosenBody) = await send(
      'POST',
      '/admin/users/$id/password',
      token: adminToken,
      body: {'new_password': 'admin-chose-this-1'},
    );
    expect(chosen, 400, reason: '$chosenBody');
    expect((await login('bob-user', 'bob-own-choice-1')).$1, 200);

    final (status, body) = await send(
      'POST',
      '/admin/users/$id/password',
      token: adminToken,
    );
    expect(status, 200, reason: '$body');
    final reset = body['one_time_password'] as String;
    expect(PasswordPolicy.validate(reset), isNull);

    expect((await login('bob-user', 'bob-own-choice-1')).$1, 401);
    expect(
      (await send('GET', '/Patient', token: bobToken)).$1,
      401,
      reason: 'the sessions from before the reset end',
    );
    expect((await login('bob-user', reset)).$1, 403);
    expect((await setOwn('bob-user', reset, 'bob-own-choice-2')).$1, 200);
    expect((await login('bob-user', 'bob-own-choice-2')).$1, 200);
  });

  test('a signed-in change of an ordinary password still works', () async {
    final (_, once) = await createBob();
    final (_, first) = await setOwn('bob-user', once, 'bob-own-choice-1');
    final (status, body) = await send(
      'POST',
      '/auth/password',
      token: first['token'] as String,
      body: {
        'current_password': 'bob-own-choice-1',
        'new_password': 'bob-own-choice-2',
      },
    );
    expect(status, 200, reason: '$body');
    expect((await login('bob-user', 'bob-own-choice-2')).$1, 200);
  });

  test('the first administrator still chooses its own password', () async {
    final server = await createTestServer(exportDir: exportDir.path);
    try {
      final r = await server.handler(
        testRequest(
          'POST',
          '/auth/register',
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'username': 'first-admin',
            'password': 'first-admin-own-1',
          }),
        ),
      );
      final text = await r.readAsString();
      expect(r.statusCode, 201, reason: text);
      final r2 = await server.handler(
        testRequest(
          'POST',
          '/auth/login',
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'username': 'first-admin',
            'password': 'first-admin-own-1',
          }),
        ),
      );
      expect(r2.statusCode, 200, reason: await r2.readAsString());
    } finally {
      await server.db.close();
    }
  });
}
