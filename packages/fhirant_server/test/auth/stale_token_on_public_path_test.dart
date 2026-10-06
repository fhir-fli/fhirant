import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../integration/test_helpers.dart';

/// REVIEW-2026-10-06 finding 1 (probe P1, `tool/review_2026-10-06/`): on a
/// public path the auth middleware injected a signature-verified token
/// without re-reading its account, so a token of an administrator who had
/// since been deactivated, or demoted, was `auth_user` with role admin, and
/// `POST /auth/register` created a new administrator with it (201). The
/// same token was 401 on every protected route. Deactivating a compromised
/// administrator is the response to a leaked credential, and it did not
/// hold. Now the public-path branch applies the four checks the protected
/// branch applies (revocation, account exists, active, current generation)
/// and treats a token that fails one as absent.
void main() {
  late FhirAntDb db;
  late Handler handler;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
  });

  tearDown(() => db.close());

  Future<String> admin(String name) => issueTestToken(
        db,
        username: name,
        role: 'admin',
        scopes: ['system/*.*'],
      );

  String registration(String username) => jsonEncode({
        'username': username,
        'password': 'a-long-enough-password-123',
        'role': 'admin',
      });

  Future<Response> register(String token, String username) async => handler(
        testRequest(
          'POST',
          '/auth/register',
          body: registration(username),
          authToken: token,
        ),
      );

  test('control: an active administrator registers an administrator', () async {
    final token = await admin('adminA');
    await admin('adminB');
    final response = await register(token, 'new-admin');
    expect(response.statusCode, 201);
    expect((await db.getUserByUsername('new-admin'))?.role, 'admin');
  });

  test("a deactivated administrator's token registers nobody", () async {
    final token = await admin('adminA');
    await admin('adminB');
    final id = (await db.getUserByUsername('adminA'))!.id;
    // As setActiveHandler does: switch off and end the sessions.
    await db.deactivateUser(id);
    await db.bumpTokenGeneration(id);

    final protected =
        await handler(testRequest('GET', '/Patient', authToken: token));
    expect(protected.statusCode, 401, reason: 'the protected route refuses it');

    final response = await register(token, 'evil-admin');
    expect(response.statusCode, 403);
    expect(await db.getUserByUsername('evil-admin'), isNull);
  });

  test("a demoted administrator's stale token registers nobody", () async {
    final token = await admin('adminA');
    await admin('adminB');
    final id = (await db.getUserByUsername('adminA'))!.id;
    // As setRoleHandler does: the role changes and the sessions end; the
    // token still says admin.
    await db.updateUserRole(id, 'readonly');
    await db.bumpTokenGeneration(id);

    final response = await register(token, 'evil-admin');
    expect(response.statusCode, 403);
    expect(await db.getUserByUsername('evil-admin'), isNull);
  });

  test('a token whose account does not exist registers nobody', () async {
    await admin('adminB');
    final token = generateTestToken(userId: 9999, role: 'admin');
    final response = await register(token, 'evil-admin');
    expect(response.statusCode, 403);
    expect(await db.getUserByUsername('evil-admin'), isNull);
  });

  test('a stale token on a public route still reaches the route anonymously',
      () async {
    final token = await admin('adminA');
    final id = (await db.getUserByUsername('adminA'))!.id;
    await db.deactivateUser(id);
    await db.bumpTokenGeneration(id);
    // /auth/status is public and needs no caller: the stale token is
    // ignored, not refused, and the route answers as to anyone.
    final response =
        await handler(testRequest('GET', '/auth/status', authToken: token));
    expect(response.statusCode, 200);
  });
}
