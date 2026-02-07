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
      when(() => mockRequest.headers).thenReturn({});
      when(
        () => mockDb.saveResource(any()),
      ).thenAnswer((_) async => true);
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'test-id'),
      ).thenAnswer((_) async => fhir.Patient.fromJson({
            'resourceType': 'Patient',
            'id': 'test-id',
            'name': [
              {'family': 'Updated'},
            ],
          }));

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
      when(() => mockRequest.headers).thenReturn({});
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
      when(() => mockRequest.headers).thenReturn({});

      final response = await putResourceHandler(
        mockRequest,
        'Patient',
        'test-id',
        mockDb,
      );

      expect(response.statusCode, equals(500));
    });

    test('returns ETag header on successful update', () async {
      final savedPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'test-id',
        'meta': {
          'versionId': '2',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Updated'},
        ],
      });
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
      when(() => mockRequest.headers).thenReturn({});
      when(
        () => mockDb.saveResource(any()),
      ).thenAnswer((_) async => true);
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'test-id'),
      ).thenAnswer((_) async => savedPatient);

      final response = await putResourceHandler(
        mockRequest,
        'Patient',
        'test-id',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      expect(response.headers['ETag'], equals('W/"2"'));
    });

    test('If-Match matching allows update', () async {
      final currentPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'test-id',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Old'},
        ],
      });
      final savedPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'test-id',
        'meta': {
          'versionId': '2',
          'lastUpdated': '2024-01-16T10:30:00.000Z',
        },
        'name': [
          {'family': 'Updated'},
        ],
      });
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
      when(() => mockRequest.headers).thenReturn({
        'if-match': 'W/"1"',
      });
      // First call is for If-Match check, second is for re-fetch after save
      var callCount = 0;
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'test-id'),
      ).thenAnswer((_) async {
        callCount++;
        return callCount == 1 ? currentPatient : savedPatient;
      });
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
      expect(response.headers['ETag'], equals('W/"2"'));
    });

    test('If-Match non-matching returns 412', () async {
      final currentPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'test-id',
        'meta': {
          'versionId': '5',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Current'},
        ],
      });
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
      when(() => mockRequest.headers).thenReturn({
        'if-match': 'W/"1"',
      });
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'test-id'),
      ).thenAnswer((_) async => currentPatient);

      final response = await putResourceHandler(
        mockRequest,
        'Patient',
        'test-id',
        mockDb,
      );

      expect(response.statusCode, equals(412));
    });

    test('If-Match when resource missing returns 412', () async {
      final patientJson = jsonEncode({
        'resourceType': 'Patient',
        'id': 'test-id',
        'name': [
          {'family': 'New'},
        ],
      });

      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => patientJson);
      when(() => mockRequest.headers).thenReturn({
        'if-match': 'W/"1"',
      });
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'test-id'),
      ).thenAnswer((_) async => null);

      final response = await putResourceHandler(
        mockRequest,
        'Patient',
        'test-id',
        mockDb,
      );

      expect(response.statusCode, equals(412));
    });

    test('no If-Match header allows update normally', () async {
      final savedPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'test-id',
        'meta': {
          'versionId': '2',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Updated'},
        ],
      });
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
      when(() => mockRequest.headers).thenReturn({});
      when(
        () => mockDb.saveResource(any()),
      ).thenAnswer((_) async => true);
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'test-id'),
      ).thenAnswer((_) async => savedPatient);

      final response = await putResourceHandler(
        mockRequest,
        'Patient',
        'test-id',
        mockDb,
      );

      expect(response.statusCode, equals(200));
    });

    test('Prefer: return=minimal returns 200 with no body', () async {
      final savedPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'test-id',
        'meta': {
          'versionId': '2',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Updated'},
        ],
      });
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
      when(() => mockRequest.headers).thenReturn({
        'prefer': 'return=minimal',
      });
      when(
        () => mockDb.saveResource(any()),
      ).thenAnswer((_) async => true);
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'test-id'),
      ).thenAnswer((_) async => savedPatient);

      final response = await putResourceHandler(
        mockRequest,
        'Patient',
        'test-id',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      expect(body, isEmpty);
      expect(response.headers['ETag'], equals('W/"2"'));
    });

    test('Prefer: return=OperationOutcome returns 200 with OO', () async {
      final savedPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'test-id',
        'meta': {
          'versionId': '2',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Updated'},
        ],
      });
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
      when(() => mockRequest.headers).thenReturn({
        'prefer': 'return=OperationOutcome',
      });
      when(
        () => mockDb.saveResource(any()),
      ).thenAnswer((_) async => true);
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'test-id'),
      ).thenAnswer((_) async => savedPatient);

      final response = await putResourceHandler(
        mockRequest,
        'Patient',
        'test-id',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('OperationOutcome'));
    });
  });
}
