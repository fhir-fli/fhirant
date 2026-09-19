// Real password hashes (Argon2id) on every login; past the 30 s default
// under the whole suite.
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-17 A14. No route changed a password, deactivated an
/// account or changed a role or scopes; a leaked password could only be
/// fixed in the database. And every such change must end the sessions
/// from before it: OWASP Session Management Cheat Sheet, "Renew the Session
/// ID After Any Privilege Level Change" (raw markdown read 2026-09-19,
/// verbatim): "Common scenarios to consider include; password changes,
/// permission changes, or switching from a regular user role to an
/// administrator role" and "the old or previous session ID must be
/// destroyed". Every token carries the account's token generation; a
/// change moves it on, and older tokens are refused on their next use.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String adminToken;
  late int aliceId;
  late Directory exportDir;
  const alicePassword = 'alice-password-1';

  setUp(() async {
    exportDir = await Directory.systemTemp.createTemp('accounts');
    final server = await createTestServer(exportDir: exportDir.path);
    db = server.db;
    handler = server.handler;
    adminToken = await issueTestToken(
      db,
      username: 'admin-one',
      role: 'admin',
      scopes: ['system/*.*'],
    );
    final salt = PasswordHasher.generateSalt();
    aliceId = await db.createUser(
      username: 'alice-user',
      passwordHash: await PasswordHasher.hashPassword(alicePassword, salt),
      salt: salt,
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

  Future<int> read(String token) async =>
      (await send('GET', '/Patient', token: token)).$1;

  group('the caller changes its own password', () {
    test('and the old sessions end, the new one works', () async {
      final (s0, before) = await login('alice-user', alicePassword);
      expect(s0, 200);
      final oldToken = before['token'] as String;
      final oldRefresh = before['refresh_token'] as String;
      expect(await read(oldToken), 200);

      final (s1, changed) = await send(
        'POST',
        '/auth/password',
        token: oldToken,
        body: {
          'current_password': alicePassword,
          'new_password': 'alice-password-2',
        },
      );
      expect(s1, 200, reason: '$changed');
      final newToken = changed['token'] as String;

      expect(await read(oldToken), 401, reason: 'the old session is over');
      expect(await read(newToken), 200, reason: 'the change hands back one');
      final (sRefresh, _) = await send(
        'POST',
        '/auth/token',
        body: {'grant_type': 'refresh_token', 'refresh_token': oldRefresh},
      );
      expect(sRefresh, 401, reason: 'the old refresh token is over too');
      expect((await login('alice-user', alicePassword)).$1, 401);
      expect((await login('alice-user', 'alice-password-2')).$1, 200);
    });

    test('needs the current password, and a new one within the policy',
        () async {
      final (_, before) = await login('alice-user', alicePassword);
      final token = before['token'] as String;
      final (wrong, _) = await send(
        'POST',
        '/auth/password',
        token: token,
        body: {
          'current_password': 'not-it',
          'new_password': 'alice-password-2',
        },
      );
      expect(wrong, 401);
      final (weak, body) = await send(
        'POST',
        '/auth/password',
        token: token,
        body: {'current_password': alicePassword, 'new_password': 'short'},
      );
      expect(weak, 400, reason: '$body');
      expect(await read(token), 200, reason: 'nothing changed');
      expect((await send('POST', '/auth/password', body: {})).$1, 401);
    });
  });

  group('an administrator', () {
    test('resets a password, and the old sessions end', () async {
      final (_, before) = await login('alice-user', alicePassword);
      final token = before['token'] as String;
      final (s, _) = await send(
        'POST',
        '/admin/users/$aliceId/password',
        token: adminToken,
        body: {'new_password': 'reset-by-admin-1'},
      );
      expect(s, 200);
      expect(await read(token), 401);
      expect((await login('alice-user', alicePassword)).$1, 401);
      expect((await login('alice-user', 'reset-by-admin-1')).$1, 200);
    });

    test('deactivates and reactivates an account', () async {
      final (_, before) = await login('alice-user', alicePassword);
      final token = before['token'] as String;
      final (s1, off) = await send(
        'POST',
        '/admin/users/$aliceId/deactivate',
        token: adminToken,
      );
      expect(s1, 200);
      expect(off['active'], isFalse);
      expect(await read(token), 401);
      expect((await login('alice-user', alicePassword)).$1, 401);
      final (s2, on) = await send(
        'POST',
        '/admin/users/$aliceId/activate',
        token: adminToken,
      );
      expect(s2, 200);
      expect(on['active'], isTrue);
      expect((await login('alice-user', alicePassword)).$1, 200);
    });

    test('changes a role, and the old sessions end', () async {
      final (_, before) = await login('alice-user', alicePassword);
      final token = before['token'] as String;
      final (s, body) = await send(
        'PUT',
        '/admin/users/$aliceId/role',
        token: adminToken,
        body: {'role': 'readonly'},
      );
      expect(s, 200, reason: '$body');
      expect(body['role'], 'readonly');
      expect(await read(token), 401);
      final (_, after) = await login('alice-user', alicePassword);
      expect(after['role'], 'readonly');
      final (bad, _) = await send(
        'PUT',
        '/admin/users/$aliceId/role',
        token: adminToken,
        body: {'role': 'superuser'},
      );
      expect(bad, 400);
    });

    test('changes scopes, and the old sessions end', () async {
      final (_, before) = await login('alice-user', alicePassword);
      final token = before['token'] as String;
      final (s, body) = await send(
        'PUT',
        '/admin/users/$aliceId/scopes',
        token: adminToken,
        body: {
          'scopes': ['user/Patient.rs'],
        },
      );
      expect(s, 200, reason: '$body');
      expect(body['scopes'], ['user/Patient.rs']);
      expect(await read(token), 401);
      final (_, after) = await login('alice-user', alicePassword);
      expect(after['scopes'], ['user/Patient.rs']);
      final (bad, _) = await send(
        'PUT',
        '/admin/users/$aliceId/scopes',
        token: adminToken,
        body: {
          'scopes': ['not a scope'],
        },
      );
      expect(bad, 400);
    });

    test('lists accounts without their secrets', () async {
      final (s, body) = await send('GET', '/admin/users', token: adminToken);
      expect(s, 200);
      final users = (body['users'] as List).cast<Map<String, dynamic>>();
      expect(users.map((u) => u['username']), contains('alice-user'));
      for (final u in users) {
        expect(u.keys, isNot(contains('password_hash')));
        expect(u.keys, isNot(contains('salt')));
        expect(u.keys, isNot(contains('passwordHash')));
      }
    });

    test('cannot deactivate or demote the last active administrator', () async {
      final admin = (await db.getUserByUsername('admin-one'))!;
      final (s1, _) = await send(
        'POST',
        '/admin/users/${admin.id}/deactivate',
        token: adminToken,
      );
      expect(s1, 409);
      final (s2, _) = await send(
        'PUT',
        '/admin/users/${admin.id}/role',
        token: adminToken,
        body: {'role': 'clinician'},
      );
      expect(s2, 409);
      expect((await db.getUserByUsername('admin-one'))!.active, isTrue);
    });

    test('is required: a clinician gets 403, an unknown id 404', () async {
      final (_, alice) = await login('alice-user', alicePassword);
      final token = alice['token'] as String;
      expect((await send('GET', '/admin/users', token: token)).$1, 403);
      expect(
        (await send(
          'POST',
          '/admin/users/$aliceId/deactivate',
          token: token,
        ))
            .$1,
        403,
      );
      expect(
        (await send(
          'POST',
          '/admin/users/999999/deactivate',
          token: adminToken,
        ))
            .$1,
        404,
      );
    });
  });

  test('a token with no generation claim is one from before the change',
      () async {
    // issueTestToken mints tokens as the server does; a change moves the
    // account on and the earlier token is refused, generation 0 < 1.
    final token = await issueTestToken(
      db,
      username: 'bob-user',
      scopes: ['user/*.rs'],
    );
    expect(await read(token), 200);
    final bob = (await db.getUserByUsername('bob-user'))!;
    await db.bumpTokenGeneration(bob.id);
    expect(await read(token), 401);
  });
}
