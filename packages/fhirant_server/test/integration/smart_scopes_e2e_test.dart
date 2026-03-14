import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  late FhirAntDb db;
  late Handler handler;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
  });

  tearDown(() async {
    await db.close();
  });

  group('Register with scopes', () {
    test('first user gets default admin scopes in response', () async {
      final response = await handler(testRequest(
        'POST',
        '/auth/register',
        body: jsonEncode({
          'username': 'admin',
          'password': 'scopeTestPass1',
        }),
      ));

      expect(response.statusCode, 201);
      final body = jsonDecode(await response.readAsString());
      expect(body['role'], 'admin');
      expect(body['scopes'], contains('system/*.*'));
    });

    test('admin can register user with custom scopes', () async {
      // Bootstrap admin
      await handler(testRequest(
        'POST',
        '/auth/register',
        body: jsonEncode({
          'username': 'admin',
          'password': 'scopeTestPass1',
        }),
      ));

      // Login admin
      final loginResp = await handler(testRequest(
        'POST',
        '/auth/login',
        body: jsonEncode({
          'username': 'admin',
          'password': 'scopeTestPass1',
        }),
      ));
      final adminToken =
          jsonDecode(await loginResp.readAsString())['token'] as String;

      // Register user with custom scopes
      final response = await handler(testRequest(
        'POST',
        '/auth/register',
        body: jsonEncode({
          'username': 'nurse',
          'password': 'scopeTestPass1',
          'role': 'clinician',
          'scopes': ['user/Patient.rs', 'user/Observation.rs'],
        }),
        authToken: adminToken,
      ));

      expect(response.statusCode, 201);
      final body = jsonDecode(await response.readAsString());
      expect(body['scopes'], contains('user/Patient.rs'));
      expect(body['scopes'], contains('user/Observation.rs'));
    });

    test('invalid scope string returns 400', () async {
      // Bootstrap admin
      await handler(testRequest(
        'POST',
        '/auth/register',
        body: jsonEncode({
          'username': 'admin',
          'password': 'scopeTestPass1',
        }),
      ));
      final loginResp = await handler(testRequest(
        'POST',
        '/auth/login',
        body: jsonEncode({
          'username': 'admin',
          'password': 'scopeTestPass1',
        }),
      ));
      final adminToken =
          jsonDecode(await loginResp.readAsString())['token'] as String;

      final response = await handler(testRequest(
        'POST',
        '/auth/register',
        body: jsonEncode({
          'username': 'baduser',
          'password': 'scopeTestPass1',
          'scopes': ['not-a-valid-scope'],
        }),
        authToken: adminToken,
      ));

      expect(response.statusCode, 400);
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('Invalid SMART scope'));
    });
  });

  group('Login returns scopes', () {
    test('login response includes scopes', () async {
      // Bootstrap admin
      await handler(testRequest(
        'POST',
        '/auth/register',
        body: jsonEncode({
          'username': 'admin',
          'password': 'scopeTestPass1',
        }),
      ));

      final response = await handler(testRequest(
        'POST',
        '/auth/login',
        body: jsonEncode({
          'username': 'admin',
          'password': 'scopeTestPass1',
        }),
      ));

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString());
      expect(body['scopes'], isA<List>());
      expect(body['scopes'], isNotEmpty);
    });
  });

  group('Scope enforcement', () {
    late String readOnlyToken;

    setUp(() async {
      // Bootstrap admin
      await handler(testRequest(
        'POST',
        '/auth/register',
        body: jsonEncode({
          'username': 'admin',
          'password': 'scopeTestPass1',
        }),
      ));

      // Login admin
      final loginResp = await handler(testRequest(
        'POST',
        '/auth/login',
        body: jsonEncode({
          'username': 'admin',
          'password': 'scopeTestPass1',
        }),
      ));
      final adminToken =
          jsonDecode(await loginResp.readAsString())['token'] as String;

      // Register readonly user
      await handler(testRequest(
        'POST',
        '/auth/register',
        body: jsonEncode({
          'username': 'reader',
          'password': 'scopeTestPass1',
          'role': 'readonly',
        }),
        authToken: adminToken,
      ));

      // Login readonly user
      final readerLogin = await handler(testRequest(
        'POST',
        '/auth/login',
        body: jsonEncode({
          'username': 'reader',
          'password': 'scopeTestPass1',
        }),
      ));
      readOnlyToken =
          jsonDecode(await readerLogin.readAsString())['token'] as String;
    });

    test('readonly user can search (GET)', () async {
      final response = await handler(testRequest(
        'GET',
        '/Patient',
        authToken: readOnlyToken,
      ));

      expect(response.statusCode, 200);
    });

    test('readonly user blocked from creating (POST)', () async {
      final response = await handler(testRequest(
        'POST',
        '/Patient',
        body: jsonEncode({
          'resourceType': 'Patient',
          'name': [
            {
              'family': 'Test',
              'given': ['User']
            }
          ]
        }),
        authToken: readOnlyToken,
      ));

      expect(response.statusCode, 403);
    });

    test('readonly user blocked from delete', () async {
      final response = await handler(testRequest(
        'DELETE',
        '/Patient/123',
        authToken: readOnlyToken,
      ));

      expect(response.statusCode, 403);
    });
  });

  group('Backward compatibility', () {
    test('legacy token without scope claim uses role defaults', () async {
      // Generate a token without scopes (like old tokens)
      final legacyToken = generateTestToken(role: 'clinician');

      // Should still work — clinician defaults to user/*.*
      final response = await handler(testRequest(
        'GET',
        '/Patient',
        authToken: legacyToken,
      ));

      expect(response.statusCode, 200);
    });

    test('legacy readonly token still blocked from writes', () async {
      final legacyToken = generateTestToken(role: 'readonly');

      final response = await handler(testRequest(
        'POST',
        '/Patient',
        body: jsonEncode({
          'resourceType': 'Patient',
          'name': [
            {
              'family': 'Test',
              'given': ['User']
            }
          ]
        }),
        authToken: legacyToken,
      ));

      expect(response.statusCode, 403);
    });
  });

  group('.well-known/smart-configuration', () {
    test('returns SMART config', () async {
      final response = await handler(testRequest(
        'GET',
        '/.well-known/smart-configuration',
      ));

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString());
      expect(body['token_endpoint'], contains('/auth/token'));
      expect(body['scopes_supported'], isA<List>());
      expect(body['capabilities'], contains('permission-v2'));
    });
  });
}
