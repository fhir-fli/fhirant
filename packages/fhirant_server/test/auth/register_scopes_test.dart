import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../integration/test_helpers.dart';

/// REVIEW-2026-10-06 finding 13 (probe P14): `POST /auth/register` with
/// `scopes: [42]` was a 500 "Registration failed", because the handler cast
/// the array's entries to String before checking them. The scopes rule is
/// `scopesError` (account_rules.dart), the one the scope change already
/// applies; registration applies it now.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String admin;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    admin = await issueTestToken(
      db,
      username: 'adm',
      role: 'admin',
      scopes: ['system/*.*'],
    );
  });

  tearDown(() => db.close());

  Future<Response> register(Object? scopes) async => handler(
        testRequest(
          'POST',
          '/auth/register',
          authToken: admin,
          body: jsonEncode({
            'username': 'newu',
            'password': 'a-long-enough-password-123',
            'scopes': scopes,
          }),
        ),
      );

  test("a non-string entry is the client's 400", () async {
    final response = await register([42]);
    expect(response.statusCode, 400);
    expect(await response.readAsString(), contains('Invalid SMART scope'));
    expect(await db.getUserByUsername('newu'), isNull);
  });

  test('a scope that does not parse is 400', () async {
    final response = await register(['nonsense']);
    expect(response.statusCode, 400);
  });

  test('scopes that are not an array are 400', () async {
    final response = await register('user/*.rs');
    expect(response.statusCode, 400);
    expect(await response.readAsString(), contains('array'));
  });

  test('control: valid scopes register and are stored', () async {
    final response = await register(['user/Patient.rs']);
    expect(response.statusCode, 201);
    final user = await db.getUserByUsername('newu');
    expect(jsonDecode(user!.scopes!), ['user/Patient.rs']);
  });
}
