// Real password hashes (Argon2id); past the 30 s default under the suite.
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-17 A12. Login told accounts apart: a deactivated account
/// was 403, an unknown one 401, a locked one 423, and the deactivated path
/// skipped the password hash.
///
/// OWASP Authentication Cheat Sheet, "Authentication Responses" (raw
/// markdown read 2026-09-19, verbatim): "an application must respond with
/// a generic error message regardless of whether: The user ID or password
/// was incorrect. The account does not exist. The account is locked or
/// disabled." And "Error Codes and URLs": a differing HTTP code "can leak
/// information about whether the account is valid or not".
void main() {
  late FhirAntDb db;
  late Handler handler;
  late Directory exportDir;

  setUp(() async {
    exportDir = await Directory.systemTemp.createTemp('login-alike');
    final server = await createTestServer(exportDir: exportDir.path);
    db = server.db;
    handler = server.handler;
    final salt = PasswordHasher.generateSalt();
    final hash = await PasswordHasher.hashPassword('right-password-1', salt);
    await db.createUser(
      username: 'active-user',
      passwordHash: hash,
      salt: salt,
    );
    final inactive = await db.createUser(
      username: 'inactive-user',
      passwordHash: hash,
      salt: salt,
    );
    await db.deactivateUser(inactive);
    final locked = await db.createUser(
      username: 'locked-user',
      passwordHash: hash,
      salt: salt,
    );
    await db.lockAccount(
      locked,
      DateTime.now().add(const Duration(minutes: 15)),
    );
  });

  tearDown(() async {
    await db.close();
    await exportDir.delete(recursive: true);
  });

  Future<(int, String)> login(String username, String password) async {
    final r = await handler(
      testRequest(
        'POST',
        '/auth/login',
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      ),
    );
    return (r.statusCode, await r.readAsString());
  }

  Future<(int, String)> authorize(String username, String password) async {
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
          'username': username,
          'password': password,
        }),
      ),
    );
    return (r.statusCode, await r.readAsString());
  }

  test('the right password on an active account logs in', () async {
    final (status, _) = await login('active-user', 'right-password-1');
    expect(status, 200);
  });

  test('wrong password, unknown, deactivated and locked answer alike',
      () async {
    final answers = {
      'wrong password': await login('active-user', 'wrong-password'),
      'unknown account': await login('nobody-here', 'right-password-1'),
      'deactivated': await login('inactive-user', 'right-password-1'),
      'locked': await login('locked-user', 'right-password-1'),
    };
    for (final entry in answers.entries) {
      expect(entry.value.$1, 401, reason: entry.key);
      expect(
        jsonDecode(entry.value.$2),
        {'error': 'Invalid username or password'},
        reason: entry.key,
      );
    }
  });

  test('the authorize form answers alike too', () async {
    final answers = {
      'wrong password': await authorize('active-user', 'wrong-password'),
      'unknown account': await authorize('nobody-here', 'right-password-1'),
      'deactivated': await authorize('inactive-user', 'right-password-1'),
      'locked': await authorize('locked-user', 'right-password-1'),
    };
    final statuses = answers.values.map((a) => a.$1).toSet();
    final bodies = answers.values.map((a) => a.$2).toSet();
    expect(statuses, hasLength(1), reason: '$answers');
    expect(bodies, hasLength(1), reason: '$answers');
    expect(statuses.single, 401);
  });
}
