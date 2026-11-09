// Real password hashes on every claim and login; past the 30 s default
// under the whole suite.
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/auth/owner_claim.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// OWASP ASVS 5.0.0 V6.4.1 (L1) and V6.4.6 (L3), official flat JSON,
/// verbatim: "system generated initial passwords or activation codes are
/// securely randomly generated, follow the existing password policy, and
/// expire after a short period of time or after they are initially used.
/// These initial secrets must not be permitted to become the long term
/// password", and "administrative users can initiate the password reset
/// process for the user, but that this does not allow them to change or
/// choose the user's password. This prevents a situation where they know
/// the user's password."
///
/// An administrator chose the password of every account it created and
/// every password it reset; then (2026-11-03) it was handed a one-time
/// password, which it could use to set one of its own choosing. Now it is
/// handed nothing: the owner sends their own password and the
/// administrator approves it with the code the owner is shown
/// (`auth/owner_claim.dart`).
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String adminToken;
  late Directory exportDir;

  setUp(() async {
    exportDir = await Directory.systemTemp.createTemp('owner_claim');
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

  Future<(int, Map<String, dynamic>)> claim(String user, String password) =>
      send(
        'POST',
        '/auth/claim',
        body: {'username': user, 'new_password': password},
      );

  Future<(int, Map<String, dynamic>)> approve(int id, String code) => send(
        'POST',
        '/admin/users/$id/approve',
        token: adminToken,
        body: {'code': code},
      );

  /// Creates `bob-user` as the administrator; returns its id and the reply.
  Future<(int, Map<String, dynamic>)> createBob() async {
    final (status, body) = await send(
      'POST',
      '/auth/register',
      token: adminToken,
      body: {'username': 'bob-user'},
    );
    expect(status, 201, reason: '$body');
    return (body['id'] as int, body);
  }

  /// Every string anywhere in [replies].
  Iterable<String> strings(Object? node) sync* {
    if (node is String) yield node;
    if (node is Map) {
      for (final v in node.values) {
        yield* strings(v);
      }
    }
    if (node is List) {
      for (final v in node) {
        yield* strings(v);
      }
    }
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

  test(
      'a new account waits for its owner; the reply has no secret and no '
      'session', () async {
    final (id, body) = await createBob();
    expect(body.containsKey('token'), isFalse);
    expect(body.containsKey('refresh_token'), isFalse);
    expect(body.keys, isNot(contains('one_time_password')));
    final until = DateTime.parse(body['awaiting_owner_until'] as String);
    final wait = until.difference(DateTime.now());
    expect(wait, lessThanOrEqualTo(ownerWaitLifetime));
    expect(wait, greaterThan(ownerWaitLifetime - const Duration(minutes: 1)));
    expect((await db.getUserById(id))!.awaitingOwnerUntil, isNotNull);
  });

  test('the owner sets their own password, approved by the code', () async {
    final (id, _) = await createBob();
    final (status, sent) = await claim('bob-user', 'bob-own-choice-1');
    expect(status, 202, reason: '$sent');
    final code = sent['code'] as String;
    final shape =
        RegExp(r'^[BCDFGHJKLMNPQRSTVWXZ]{4}-[BCDFGHJKLMNPQRSTVWXZ]{4}$');
    expect(code, matches(shape));
    expect(
      (await login('bob-user', 'bob-own-choice-1')).$1,
      401,
      reason: 'not before the administrator approves it',
    );
    final (approved, user) = await approve(id, code);
    expect(approved, 200, reason: '$user');
    expect(user.containsKey('awaiting_owner_until'), isFalse);
    expect((await login('bob-user', 'bob-own-choice-1')).$1, 200);
    expect(
      (await approve(id, code)).$1,
      409,
      reason: 'a code approves once',
    );
  });

  test('the code is read without dashes and in any case (RFC 8628 §6.1)',
      () async {
    final (id, _) = await createBob();
    final (_, sent) = await claim('bob-user', 'bob-own-choice-1');
    final typed = (sent['code'] as String).replaceAll('-', '').toLowerCase();
    expect((await approve(id, typed)).$1, 200);
    expect((await login('bob-user', 'bob-own-choice-1')).$1, 200);
  });

  test('a wrong code drops what the owner sent; a non-code does not', () async {
    final (id, _) = await createBob();
    final (_, sent) = await claim('bob-user', 'bob-own-choice-1');
    final code = sent['code'] as String;
    expect((await approve(id, 'not a code')).$1, 400);
    final wrong = code.startsWith('B') ? 'CCCC-CCCC' : 'BBBB-BBBB';
    expect((await approve(id, wrong)).$1, 400);
    expect(
      (await approve(id, code)).$1,
      409,
      reason: 'one try per code: the owner sends it again',
    );
    expect((await login('bob-user', 'bob-own-choice-1')).$1, 401);
    final (_, again) = await claim('bob-user', 'bob-own-choice-1');
    expect((await approve(id, again['code'] as String)).$1, 200);
    expect((await login('bob-user', 'bob-own-choice-1')).$1, 200);
  });

  test('a later password replaces the earlier one', () async {
    final (id, _) = await createBob();
    final (_, first) = await claim('bob-user', 'bob-own-choice-1');
    final (_, second) = await claim('bob-user', 'bob-own-choice-2');
    expect(second['code'], isNot(first['code']));
    expect((await approve(id, second['code'] as String)).$1, 200);
    expect((await login('bob-user', 'bob-own-choice-1')).$1, 401);
    expect((await login('bob-user', 'bob-own-choice-2')).$1, 200);
  });

  test('the password the owner sends must meet the policy', () async {
    await createBob();
    expect((await claim('bob-user', 'short')).$1, 400);
  });

  test(
      'a claim for an account that does not wait looks the same and '
      'approves nothing', () async {
    final (id, _) = await createBob();
    final (_, sent) = await claim('bob-user', 'bob-own-choice-1');
    expect((await approve(id, sent['code'] as String)).$1, 200);

    for (final name in ['bob-user', 'nobody-at-all']) {
      final (status, body) = await claim(name, 'someone-else-1');
      expect(status, 202, reason: name);
      expect(body.keys, unorderedEquals(sent.keys), reason: name);
    }
    expect((await login('bob-user', 'someone-else-1')).$1, 401);
    expect((await login('bob-user', 'bob-own-choice-1')).$1, 200);
    expect((await db.getUserById(id))!.claimSent, isFalse);
  });

  test('the wait runs out: nothing is held or approved after it', () async {
    final (id, _) = await createBob();
    final (_, sent) = await claim('bob-user', 'bob-own-choice-1');
    // The wait runs out with the owner's password still held.
    await db.customStatement(
      'UPDATE users SET awaiting_owner_until = ? WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch ~/ 1000 - 1, id],
    );
    expect((await db.getUserById(id))!.claimSent, isTrue);
    final (status, body) = await approve(id, sent['code'] as String);
    expect(status, 409);
    expect(body['error'], contains('ran out'));
    final (_, late) = await claim('bob-user', 'bob-own-choice-1');
    expect((await approve(id, late['code'] as String)).$1, 409);
    expect((await login('bob-user', 'bob-own-choice-1')).$1, 401);
  });

  test(
      'a reset hands the administrator nothing, ends the old password and '
      'every session, and the owner sets a new one', () async {
    final registered = await registerByAdmin(
      handler,
      adminToken,
      {'username': 'bob-user'},
      password: 'bob-own-choice-1',
    );
    final id = registered['id'] as int;
    final bobToken = registered['token'] as String;

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
    expect(body['awaiting_owner_until'], isA<String>());
    expect(body['password_sent'], isFalse);
    expect((await login('bob-user', 'bob-own-choice-1')).$1, 401);
    expect(
      (await send('GET', '/Patient', token: bobToken)).$1,
      401,
      reason: 'the sessions from before the reset end',
    );
    final (_, sent) = await claim('bob-user', 'bob-own-choice-2');
    expect((await approve(id, sent['code'] as String)).$1, 200);
    expect((await login('bob-user', 'bob-own-choice-2')).$1, 200);
  });

  test('nothing an administrator is handed signs in as the user', () async {
    final handed = <Object?>[];
    final (id, created) = await createBob();
    final made = (await db.getUserById(id))!;
    Future<Map<String, dynamic>> users() async =>
        (await send('GET', '/admin/users', token: adminToken)).$2;
    handed
      ..add(created)
      ..add(await users());
    final (_, sent) = await claim('bob-user', 'bob-own-choice-1');
    final firstCode = sent['code'] as String;
    handed.add((await approve(id, firstCode)).$2);
    final reset =
        (await send('POST', '/admin/users/$id/password', token: adminToken)).$2;
    handed
      ..add(reset)
      ..add(await users());
    final waiting = (await db.getUserById(id))!;
    final (_, again) = await claim('bob-user', 'bob-own-choice-2');
    final secondCode = again['code'] as String;
    handed
      ..add(await users())
      ..add((await approve(id, secondCode)).$2);

    // Checked against the stored hashes, not by signing in: five wrong
    // sign-ins lock the account, and a locked 401 would prove nothing.
    final own = (await db.getUserById(id))!;
    Future<bool> opens(User u, String p) =>
        PasswordHasher.verifyPassword(p, u.salt, u.passwordHash);
    expect(await opens(own, 'bob-own-choice-2'), isTrue, reason: 'control');
    final candidates = {...handed.expand(strings), firstCode, secondCode};
    expect(candidates.length, greaterThan(5));
    for (final c in candidates) {
      expect(await opens(made, c), isFalse, reason: 'when made: $c');
      expect(await opens(waiting, c), isFalse, reason: 'after reset: $c');
      expect(await opens(own, c), isFalse, reason: c);
    }
    expect((await login('bob-user', 'bob-own-choice-2')).$1, 200);
  });

  test('only an administrator approves', () async {
    final (id, _) = await createBob();
    final (_, sent) = await claim('bob-user', 'bob-own-choice-1');
    final clinician = await issueTestToken(
      db,
      username: 'clin-one',
    );
    final (status, _) = await send(
      'POST',
      '/admin/users/$id/approve',
      token: clinician,
      body: {'code': sent['code']},
    );
    expect(status, 403);
    expect((await login('bob-user', 'bob-own-choice-1')).$1, 401);
  });

  test('an administrator cannot reset its own password', () async {
    final adminId = (await db.getUserByUsername('admin-one'))!.id;
    final (status, body) = await send(
      'POST',
      '/admin/users/$adminId/password',
      token: adminToken,
    );
    expect(status, 409, reason: '$body');
    expect((await db.getUserById(adminId))!.awaitingOwnerUntil, isNull);
    expect(
      (await send('GET', '/admin/users', token: adminToken)).$1,
      200,
      reason: 'its session goes on',
    );
  });

  test('a code taken before a reset opens no session', () async {
    final registered = await registerByAdmin(
      handler,
      adminToken,
      {'username': 'bob-user'},
      password: 'bob-own-choice-1',
    );
    final id = registered['id'] as int;
    // RFC 7636 Appendix B's verifier and challenge.
    const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
    const challenge = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';
    final (authorized, auth) = await send(
      'POST',
      '/auth/authorize',
      body: {
        'response_type': 'code',
        'state': 'xyz',
        'aud': 'http://localhost:8080',
        'client_id': 'app',
        'redirect_uri': 'http://localhost/cb',
        'scope': 'user/*.rs',
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'username': 'bob-user',
        'password': 'bob-own-choice-1',
      },
    );
    expect(authorized, 200, reason: '$auth');
    expect(
      (await send('POST', '/admin/users/$id/password', token: adminToken)).$1,
      200,
    );
    final (exchanged, tokens) = await send(
      'POST',
      '/auth/token',
      body: {
        'grant_type': 'authorization_code',
        'code': auth['code'],
        'redirect_uri': 'http://localhost/cb',
        'client_id': 'app',
        'code_verifier': verifier,
      },
    );
    expect(exchanged, 400, reason: '$tokens');
    expect(tokens['error'], 'invalid_grant');
    expect(tokens.containsKey('access_token'), isFalse);
  });

  test('a code taken with no change since still opens a session', () async {
    await registerByAdmin(
      handler,
      adminToken,
      {'username': 'bob-user'},
      password: 'bob-own-choice-1',
    );
    const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
    const challenge = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';
    final (_, auth) = await send(
      'POST',
      '/auth/authorize',
      body: {
        'response_type': 'code',
        'state': 'xyz',
        'aud': 'http://localhost:8080',
        'client_id': 'app',
        'redirect_uri': 'http://localhost/cb',
        'scope': 'user/*.rs',
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'username': 'bob-user',
        'password': 'bob-own-choice-1',
      },
    );
    final (exchanged, tokens) = await send(
      'POST',
      '/auth/token',
      body: {
        'grant_type': 'authorization_code',
        'code': auth['code'],
        'redirect_uri': 'http://localhost/cb',
        'client_id': 'app',
        'code_verifier': verifier,
      },
    );
    expect(exchanged, 200, reason: '$tokens');
    expect(tokens['access_token'], isA<String>());
  });

  test('a claim spends the credential bucket, not the general one', () async {
    final server = await createTestServer(
      exportDir: exportDir.path,
      maxRequests: 50,
      authMaxRequests: 2,
    );
    try {
      final statuses = <int>[
        for (var i = 0; i < 4; i++)
          (await server.handler(
            testRequest(
              'POST',
              '/auth/claim',
              headers: {'content-type': 'application/json'},
              body: jsonEncode({
                'username': 'nobody',
                'new_password': 'someone-else-1',
              }),
            ),
          ))
              .statusCode,
      ];
      expect(statuses.last, 429, reason: 'got $statuses');
      final other = await server.handler(testRequest('GET', '/health'));
      expect(other.statusCode, isNot(429), reason: 'control');
    } finally {
      await server.db.close();
    }
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
