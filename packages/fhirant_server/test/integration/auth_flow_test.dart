import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:test/test.dart';
import 'package:shelf/shelf.dart';

import 'test_helpers.dart';

void main() {
  late FhirAntDb testDb;
  late Handler handler;

  setUp(() async {
    final server = await createTestServer();
    testDb = server.db;
    handler = server.handler;
  });

  tearDown(() async {
    await testDb.close();
  });

  group('Auth Flow Integration Tests', () {
    test('First-user register creates admin without auth', () async {
      final response = await handler(testRequest(
        'POST',
        '/auth/register',
        body: jsonEncode({
          'username': 'firstadmin',
          'password': 'securepass123',
        }),
        headers: {'content-type': 'application/fhir+json'},
      ));

      expect(response.statusCode, equals(201));
      final body = jsonDecode(await response.readAsString());
      expect(body['username'], equals('firstadmin'));
      expect(body['role'], equals('admin'));
    });

    test('Login with registered user returns JWT token', () async {
      // Register first user (bootstrap admin)
      await handler(testRequest(
        'POST',
        '/auth/register',
        body: jsonEncode({
          'username': 'logintest',
          'password': 'testpass123',
        }),
        headers: {'content-type': 'application/fhir+json'},
      ));

      // Login
      final response = await handler(testRequest(
        'POST',
        '/auth/login',
        body: jsonEncode({
          'username': 'logintest',
          'password': 'testpass123',
        }),
        headers: {'content-type': 'application/fhir+json'},
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['token'], isNotNull);
      expect(body['token'], isNotEmpty);
      expect(body['username'], equals('logintest'));
      expect(body['role'], equals('admin'));
    });

    test('Authenticated GET /Patient works with login token', () async {
      // Register + Login
      await handler(testRequest(
        'POST',
        '/auth/register',
        body: jsonEncode({
          'username': 'authuser',
          'password': 'authpass123',
        }),
        headers: {'content-type': 'application/fhir+json'},
      ));

      final loginResponse = await handler(testRequest(
        'POST',
        '/auth/login',
        body: jsonEncode({
          'username': 'authuser',
          'password': 'authpass123',
        }),
        headers: {'content-type': 'application/fhir+json'},
      ));

      final loginBody = jsonDecode(await loginResponse.readAsString());
      final token = loginBody['token'] as String;

      // Create a patient via DB directly
      await testDb.saveResource(fhir.Patient(
        id: 'auth-test-1'.toFhirString,
        name: [fhir.HumanName(family: 'AuthTest'.toFhirString)],
      ));

      // Use the login token to GET patient
      final response = await handler(testRequest(
        'GET',
        '/Patient/auth-test-1',
        authToken: token,
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['name'][0]['family'], equals('AuthTest'));
    });

    test('Unauthenticated GET /Patient returns 401', () async {
      final response = await handler(testRequest(
        'GET',
        '/Patient',
      ));

      expect(response.statusCode, equals(401));
      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], equals('OperationOutcome'));
    });

    test('Readonly user POST /Patient returns 403', () async {
      final readonlyToken = generateTestToken(role: 'readonly');

      final response = await handler(testRequest(
        'POST',
        '/Patient',
        body: fhir.Patient(
          name: [fhir.HumanName(family: 'Forbidden'.toFhirString)],
        ).toJsonString(),
        headers: {'content-type': 'application/fhir+json'},
        authToken: readonlyToken,
      ));

      expect(response.statusCode, equals(403));
      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], equals('OperationOutcome'));
    });
  });
}
