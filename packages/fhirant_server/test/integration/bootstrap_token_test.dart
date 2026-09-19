// Real Argon2id hashes on registration.
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/fhirant_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-17 A15: with a bootstrap token issued, the first
/// `POST /auth/register` must carry it; without one the first registration
/// stays open (the app provisions locally and passes none).
void main() {
  late FhirAntDb db;
  late Handler handler;
  late Directory exportDir;
  late String token;

  setUp(() async {
    exportDir = await Directory.systemTemp.createTemp('bootstrap');
    token = generateBootstrapToken();
    final server = await createTestServer(
      exportDir: exportDir.path,
      bootstrapToken: token,
    );
    db = server.db;
    handler = server.handler;
  });

  tearDown(() async {
    await db.close();
    await exportDir.delete(recursive: true);
  });

  Future<(int, Map<String, dynamic>)> register(
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    String? authToken,
  }) async {
    final r = await handler(
      testRequest(
        'POST',
        '/auth/register',
        authToken: authToken,
        headers: {'content-type': 'application/json', ...?headers},
        body: jsonEncode(body),
      ),
    );
    return (
      r.statusCode,
      jsonDecode(await r.readAsString()) as Map<String, dynamic>,
    );
  }

  Future<Map<String, dynamic>> status() async {
    final r = await handler(testRequest('GET', '/auth/status'));
    return jsonDecode(await r.readAsString()) as Map<String, dynamic>;
  }

  const first = {'username': 'first-admin', 'password': 'First-Password-1'};

  test('the status says a token is required, until an account exists',
      () async {
    expect(await status(), {'firstUser': true, 'bootstrapTokenRequired': true});
    await register(first, headers: {'x-bootstrap-token': token});
    expect(
      await status(),
      {'firstUser': false, 'bootstrapTokenRequired': false},
    );
  });

  test('the first registration without the token is refused', () async {
    final (s, body) = await register(first);
    expect(s, 403);
    expect(body['error'], contains('bootstrap token'));
    expect(await db.getUserCount(), 0);
  });

  test('a wrong token is refused', () async {
    final (s, _) = await register(
      first,
      headers: {'x-bootstrap-token': generateBootstrapToken()},
    );
    expect(s, 403);
    final (s2, _) = await register(
      first,
      headers: {'x-bootstrap-token': token.substring(0, token.length - 1)},
    );
    expect(s2, 403);
    expect(await db.getUserCount(), 0);
  });

  test('the token in the header creates the administrator', () async {
    final (s, body) = await register(
      first,
      headers: {'x-bootstrap-token': token},
    );
    expect(s, 201, reason: '$body');
    expect(body['role'], 'admin');
    expect(body['token'], isA<String>());
  });

  test('the token in the body works too', () async {
    final (s, body) = await register({...first, 'bootstrap_token': token});
    expect(s, 201, reason: '$body');
    expect(body['role'], 'admin');
  });

  test(
      'once an account exists the token opens nothing: registration '
      'needs an administrator', () async {
    await register(first, headers: {'x-bootstrap-token': token});
    final (s, _) = await register(
      {'username': 'second-user', 'password': 'Second-Password-1'},
      headers: {'x-bootstrap-token': token},
    );
    expect(s, 403);
    final admin = await issueTestToken(
      db,
      username: 'first-admin',
      role: 'admin',
      scopes: ['system/*.*'],
    );
    final (s2, body) = await register(
      {'username': 'second-user', 'password': 'Second-Password-1'},
      authToken: admin,
    );
    expect(s2, 201, reason: '$body');
  });

  test(
      'a server with no bootstrap token leaves the first registration '
      'open, as the app relies on', () async {
    final open = await createTestServer(exportDir: exportDir.path);
    addTearDown(open.db.close);
    final r = await open.handler(
      testRequest(
        'POST',
        '/auth/register',
        headers: {'content-type': 'application/json'},
        body: jsonEncode(first),
      ),
    );
    expect(r.statusCode, 201);
    final s = await open.handler(testRequest('GET', '/auth/status'));
    expect(
      jsonDecode(await s.readAsString()),
      {'firstUser': false, 'bootstrapTokenRequired': false},
    );
  });
}
