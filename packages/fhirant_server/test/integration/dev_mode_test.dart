import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:test/test.dart';
import 'package:shelf/shelf.dart';

import 'test_helpers.dart';

void main() {
  late FhirAntDb testDb;
  late Handler handler;

  setUp(() async {
    final server = await createTestServer(devMode: true);
    testDb = server.db;
    handler = server.handler;
  });

  tearDown(() async {
    await testDb.close();
  });

  group('Dev Mode', () {
    test('allows unauthenticated requests to protected endpoints', () async {
      // Create a Patient without any auth token
      final response = await handler(testRequest(
        'POST',
        '/Patient',
        body: jsonEncode({
          'resourceType': 'Patient',
          'name': [
            {
              'family': 'TestDev',
              'given': ['Mode'],
            }
          ],
        }),
        headers: {'content-type': 'application/fhir+json'},
      ));

      expect(response.statusCode, equals(201));
      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], equals('Patient'));
      expect(body['name'][0]['family'], equals('TestDev'));
    });

    test('allows unauthenticated search', () async {
      final response = await handler(testRequest(
        'GET',
        '/Patient',
        headers: {'content-type': 'application/fhir+json'},
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], equals('Bundle'));
    });

    test('allows unauthenticated read by ID', () async {
      // First create a resource
      final createResponse = await handler(testRequest(
        'POST',
        '/Patient',
        body: jsonEncode({
          'resourceType': 'Patient',
          'name': [
            {'family': 'ReadTest'}
          ],
        }),
        headers: {'content-type': 'application/fhir+json'},
      ));
      final created = jsonDecode(await createResponse.readAsString());
      final id = created['id'];

      // Read it back without auth
      final response = await handler(testRequest(
        'GET',
        '/Patient/$id',
        headers: {'content-type': 'application/fhir+json'},
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['id'], equals(id));
    });

    test('allows unauthenticated delete', () async {
      // Create a resource
      final createResponse = await handler(testRequest(
        'POST',
        '/Patient',
        body: jsonEncode({
          'resourceType': 'Patient',
          'name': [
            {'family': 'DeleteTest'}
          ],
        }),
        headers: {'content-type': 'application/fhir+json'},
      ));
      final created = jsonDecode(await createResponse.readAsString());
      final id = created['id'];

      // Delete without auth
      final response = await handler(testRequest(
        'DELETE',
        '/Patient/$id',
        headers: {'content-type': 'application/fhir+json'},
      ));

      expect(response.statusCode, equals(204));
    });

    test('injects dev-mode auth_user for audit trail', () async {
      // Create a resource — this exercises the full pipeline
      // including audit middleware which reads auth_user
      final response = await handler(testRequest(
        'POST',
        '/Observation',
        body: jsonEncode({
          'resourceType': 'Observation',
          'status': 'final',
          'code': {
            'text': 'Dev mode test',
          },
        }),
        headers: {'content-type': 'application/fhir+json'},
      ));

      expect(response.statusCode, equals(201));
    });

    test('public routes still work', () async {
      // Health endpoint
      final healthResponse = await handler(testRequest('GET', '/health'));
      expect(healthResponse.statusCode, equals(200));

      // Metadata
      final metadataResponse =
          await handler(testRequest('GET', '/metadata'));
      expect(metadataResponse.statusCode, equals(200));

      // SMART config
      final smartResponse = await handler(
          testRequest('GET', '/.well-known/smart-configuration'));
      expect(smartResponse.statusCode, equals(200));
    });

    test('auth endpoints still work for registration', () async {
      final response = await handler(testRequest(
        'POST',
        '/auth/register',
        body: jsonEncode({
          'username': 'devuser',
          'password': 'securepass123',
        }),
        headers: {'content-type': 'application/fhir+json'},
      ));

      expect(response.statusCode, equals(201));
    });
  });

  group('Auth Mode (devMode: false)', () {
    late FhirAntDb authDb;
    late Handler authHandler;

    setUp(() async {
      final server = await createTestServer(devMode: false);
      authDb = server.db;
      authHandler = server.handler;
    });

    tearDown(() async {
      await authDb.close();
    });

    test('rejects unauthenticated requests to protected endpoints', () async {
      final response = await authHandler(testRequest(
        'GET',
        '/Patient',
        headers: {'content-type': 'application/fhir+json'},
      ));

      expect(response.statusCode, equals(401));
    });

    test('accepts authenticated requests', () async {
      final token = generateTestToken(role: 'admin');
      final response = await authHandler(testRequest(
        'GET',
        '/Patient',
        headers: {'content-type': 'application/fhir+json'},
        authToken: token,
      ));

      expect(response.statusCode, equals(200));
    });
  });
}
