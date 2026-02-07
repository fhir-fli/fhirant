import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:test/test.dart';
import 'package:shelf/shelf.dart';

import 'test_helpers.dart';

void main() {
  late FhirAntDb testDb;
  late Handler handler;
  late String authToken;

  setUp(() async {
    final server = await createTestServer();
    testDb = server.db;
    handler = server.handler;
    authToken = generateTestToken();
  });

  tearDown(() async {
    await testDb.close();
  });

  group('Middleware Pipeline Integration Tests', () {
    test('OPTIONS /Patient returns 204 with CORS headers', () async {
      final response = await handler(testRequest(
        'OPTIONS',
        '/Patient',
        headers: {
          'origin': 'http://example.com',
          'access-control-request-method': 'GET',
        },
      ));

      expect(response.statusCode, equals(204));
      expect(response.headers['access-control-allow-origin'], isNotNull);
      expect(response.headers['access-control-allow-methods'], isNotNull);
      expect(
        response.headers['access-control-allow-methods'],
        contains('GET'),
      );
    });

    test('GET response has application/fhir+json Content-Type', () async {
      await testDb.saveResource(fhir.Patient(
        id: 'ct-test-1'.toFhirString,
        name: [fhir.HumanName(family: 'ContentType'.toFhirString)],
      ));

      final response = await handler(testRequest(
        'GET',
        '/Patient/ct-test-1',
        headers: {'accept': 'application/fhir+json'},
        authToken: authToken,
      ));

      expect(response.statusCode, equals(200));
      expect(
        response.headers['content-type'],
        contains('application/fhir+json'),
      );
    });

    test('POST /Patient creates AuditEvent in DB', () async {
      final patient = fhir.Patient(
        id: 'audit-test-1'.toFhirString,
        name: [fhir.HumanName(family: 'AuditTest'.toFhirString)],
      );

      await handler(testRequest(
        'POST',
        '/Patient',
        body: patient.toJsonString(),
        headers: {'content-type': 'application/fhir+json'},
        authToken: authToken,
      ));

      // Audit middleware is fire-and-forget, wait for it to complete
      await Future.delayed(const Duration(milliseconds: 100));

      // Search for AuditEvents in the DB
      final auditEvents = await testDb.getResourcesByType(
        fhir.R4ResourceType.AuditEvent,
      );

      expect(auditEvents, isNotEmpty);

      final auditJson = auditEvents.first.toJson();
      expect(auditJson['resourceType'], equals('AuditEvent'));
    });

    test('Accept: application/xml returns 406', () async {
      final response = await handler(testRequest(
        'GET',
        '/Patient',
        headers: {'accept': 'application/xml'},
        authToken: authToken,
      ));

      expect(response.statusCode, equals(406));
    });

    test('GET /metadata returns 200 without authentication', () async {
      final response = await handler(testRequest(
        'GET',
        '/metadata',
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], equals('CapabilityStatement'));
    });
  });
}
