import 'dart:convert';
import 'dart:io';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/services/backup_service.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../integration/test_helpers.dart';

/// Two stores signing with one secret (REVIEW-2026-10-17, OWASP ASVS 5.0.0
/// V10.3.3, "an OAuth resource server only accepts access tokens that are
/// intended for use with that service (audience)"). A token named its
/// account by id, which restarts at 1 in every store, and carried its role,
/// so store X's token for its id 16 opened store Y as Y's id 16 with X's
/// role (probe of 2026-11-21, tool/review_2026-10-17/asvs_notprobed.py).
/// RFC 9068 §2.2 (read 2026-11-21) requires `sub`, `iss` and `aud`; §4
/// requires a resource server to refuse a token whose `iss` is not its
/// issuer or whose `aud` does not name it. Both stores here are built with
/// [testJwtSecret], the shared secret of the probe.
void main() {
  late Directory tmp;
  const password = 'a-long-enough-password-1';

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('token-names-account');
  });
  tearDown(() => tmp.delete(recursive: true));

  Future<void> account(FhirAntDb db, String username, String role) async {
    final salt = PasswordHasher.generateSalt();
    await db.createUser(
      username: username,
      passwordHash: await PasswordHasher.hashPassword(password, salt),
      salt: salt,
      role: role,
    );
  }

  Future<String> login(Handler handler, String username) async {
    final r = await handler(
      testRequest(
        'POST',
        '/auth/login',
        body: jsonEncode({'username': username, 'password': password}),
        headers: {'content-type': 'application/json'},
      ),
    );
    expect(r.statusCode, 200, reason: 'login $username');
    return (jsonDecode(await r.readAsString()) as Map)['token'] as String;
  }

  Future<int> adminUsers(Handler handler, String token) async =>
      (await handler(testRequest('GET', '/admin/users', authToken: token)))
          .statusCode;

  test("another store's token for the same id opens nothing here", () async {
    final x = await createTestServer();
    final y = await createTestServer();
    addTearDown(x.db.close);
    addTearDown(y.db.close);
    await account(x.db, 'xadmin', 'admin');
    await account(y.db, 'yclin', 'clinician');
    expect(
      (await x.db.getUserByUsername('xadmin'))!.id,
      (await y.db.getUserByUsername('yclin'))!.id,
      reason: 'control: both are id 1',
    );
    final token = await login(x.handler, 'xadmin');
    expect(await adminUsers(x.handler, token), 200, reason: 'control');
    expect(await adminUsers(y.handler, token), 401);
    final read =
        await y.handler(testRequest('GET', '/Patient', authToken: token));
    expect(read.statusCode, 401);
  });

  test("a restored account is found by its token; its role is the store's",
      () async {
    final x = await createTestServer();
    final y = await createTestServer();
    addTearDown(x.db.close);
    addTearDown(y.db.close);
    await account(y.db, 'ylocal', 'clinician');
    await account(x.db, 'cara', 'admin');
    final token = await login(x.handler, 'cara');

    final file = await BackupService.createFile(
      x.db,
      'correct horse battery',
      '${tmp.path}/x.sqlite',
    );
    await y.db.restoreEncrypted(file.path, 'correct horse battery');
    final onY = (await y.db.getUserByUsername('cara'))!;
    expect(
      onY.id,
      isNot((await x.db.getUserByUsername('cara'))!.id),
      reason: 'renumbered past ylocal',
    );
    expect(onY.accountKey, (await x.db.getUserByUsername('cara'))!.accountKey);
    expect(await adminUsers(y.handler, token), 200);

    // The role is read from this store's account, not from the token.
    await y.db.updateUserRole(onY.id, 'clinician');
    expect(await adminUsers(y.handler, token), 403);
  });

  test('with base URLs set, a token from the other server is refused',
      () async {
    final x = await createTestServer(baseUrl: 'https://x.example');
    final y = await createTestServer(baseUrl: 'https://y.example');
    addTearDown(x.db.close);
    addTearDown(y.db.close);
    await account(x.db, 'cara', 'admin');
    final token = await login(x.handler, 'cara');
    expect(await adminUsers(x.handler, token), 200, reason: 'control');
    final file = await BackupService.createFile(
      x.db,
      'correct horse battery',
      '${tmp.path}/x2.sqlite',
    );
    await y.db.restoreEncrypted(file.path, 'correct horse battery');
    expect(await adminUsers(y.handler, token), 401);
  });
}
