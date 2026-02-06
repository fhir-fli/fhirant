import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:fhirant_server/src/handlers/resource_handler.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

class MockRequest extends Mock implements Request {}

void main() {
  setUpAll(() {
    registerFallbackValue(fhir.R4ResourceType.Patient);
    registerFallbackValue(fhir.Patient());
  });

  group('putResourceHandler', () {
    late MockFhirAntDb mockDb;
    late MockRequest mockRequest;

    setUp(() {
      mockDb = MockFhirAntDb();
      mockRequest = MockRequest();
    });

    test('returns 200 when resource updated successfully', () async {
      final patientJson = jsonEncode({
        'resourceType': 'Patient',
        'id': 'test-id',
        'name': [
          {'family': 'Updated'},
        ],
      });

      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => patientJson);
      when(
        () => mockDb.saveResource(any()),
      ).thenAnswer((_) async => true);

      final response = await putResourceHandler(
        mockRequest,
        'Patient',
        'test-id',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('Patient'));
      expect(json['id'], equals('test-id'));
    });

    test('returns 400 when resource type mismatches URL', () async {
      final observationJson = jsonEncode({
        'resourceType': 'Observation',
        'id': 'test-id',
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '12345-6'},
          ],
        },
      });

      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => observationJson);

      final response = await putResourceHandler(
        mockRequest,
        'Patient',
        'test-id',
        mockDb,
      );

      expect(response.statusCode, equals(400));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('OperationOutcome'));
    });

    test('returns 400 when resource ID mismatches URL', () async {
      final patientJson = jsonEncode({
        'resourceType': 'Patient',
        'id': 'other-id',
        'name': [
          {'family': 'Test'},
        ],
      });

      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => patientJson);

      final response = await putResourceHandler(
        mockRequest,
        'Patient',
        'test-id',
        mockDb,
      );

      expect(response.statusCode, equals(400));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('OperationOutcome'));
    });

    test('returns 500 when database save fails', () async {
      final patientJson = jsonEncode({
        'resourceType': 'Patient',
        'id': 'test-id',
        'name': [
          {'family': 'Test'},
        ],
      });

      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => patientJson);
      when(
        () => mockDb.saveResource(any()),
      ).thenAnswer((_) async => false);

      final response = await putResourceHandler(
        mockRequest,
        'Patient',
        'test-id',
        mockDb,
      );

      expect(response.statusCode, equals(500));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('OperationOutcome'));
    });

    test('returns 500 when database throws exception', () async {
      final patientJson = jsonEncode({
        'resourceType': 'Patient',
        'id': 'test-id',
        'name': [
          {'family': 'Test'},
        ],
      });

      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => patientJson);
      when(
        () => mockDb.saveResource(any()),
      ).thenThrow(Exception('Database error'));

      final response = await putResourceHandler(
        mockRequest,
        'Patient',
        'test-id',
        mockDb,
      );

      expect(response.statusCode, equals(500));
    });
  });
}
