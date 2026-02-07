import 'dart:convert';

import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:fhirant_server/src/handlers/patch_handler.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

class MockRequest extends Mock implements Request {}

void main() {
  setUpAll(() {
    registerFallbackValue(fhir.R4ResourceType.Patient);
    registerFallbackValue(fhir.Patient());
  });

  group('patchResourceHandler', () {
    late MockFhirAntDb mockDb;
    late MockRequest mockRequest;

    setUp(() {
      mockDb = MockFhirAntDb();
      mockRequest = MockRequest();
    });

    test('returns 200 when JSON Patch applied successfully', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'name': [
          {'family': 'OldName'},
        ],
      });
      final patchedPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {
          'versionId': '2',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'NewName'},
        ],
      });

      final patchBody = jsonEncode([
        {'op': 'replace', 'path': '/name/0/family', 'value': 'NewName'},
      ]);

      var callCount = 0;
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async {
        callCount++;
        return callCount == 1 ? patient : patchedPatient;
      });
      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => patchBody);
      when(
        () => mockRequest.headers,
      ).thenReturn({});
      when(
        () => mockDb.saveResource(any()),
      ).thenAnswer((_) async => true);

      final response = await patchResourceHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('Patient'));
      final names = json['name'] as List;
      expect(names[0]['family'], equals('NewName'));
    });

    test('returns 404 when resource not found', () async {
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => null);

      final response = await patchResourceHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(404));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['error'], equals('Resource not found'));
    });

    test('returns 400 for invalid resource type', () async {
      final response = await patchResourceHandler(
        mockRequest,
        'InvalidType',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(400));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('OperationOutcome'));
    });

    test('returns 400 for invalid JSON patch body', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'name': [
          {'family': 'Test'},
        ],
      });

      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => patient);
      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => 'not json');

      final response = await patchResourceHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(400));
    });

    test('returns 400 when patch changes resource type', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'name': [
          {'family': 'Test'},
        ],
      });

      final patchBody = jsonEncode([
        {'op': 'replace', 'path': '/resourceType', 'value': 'Observation'},
      ]);

      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => patient);
      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => patchBody);

      final response = await patchResourceHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(400));
    });

    test('returns 400 when patch changes resource ID', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'name': [
          {'family': 'Test'},
        ],
      });

      final patchBody = jsonEncode([
        {'op': 'replace', 'path': '/id', 'value': 'other-id'},
      ]);

      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => patient);
      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => patchBody);

      final response = await patchResourceHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(400));
    });

    test('returns 500 when save fails', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'name': [
          {'family': 'OldName'},
        ],
      });

      final patchBody = jsonEncode([
        {'op': 'replace', 'path': '/name/0/family', 'value': 'NewName'},
      ]);

      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => patient);
      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => patchBody);
      when(
        () => mockDb.saveResource(any()),
      ).thenAnswer((_) async => false);

      final response = await patchResourceHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(500));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('OperationOutcome'));
    });

    test('returns ETag header on successful patch', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'name': [
          {'family': 'OldName'},
        ],
      });
      final savedPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {
          'versionId': '2',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'NewName'},
        ],
      });

      final patchBody = jsonEncode([
        {'op': 'replace', 'path': '/name/0/family', 'value': 'NewName'},
      ]);

      var callCount = 0;
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async {
        callCount++;
        return callCount == 1 ? patient : savedPatient;
      });
      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => patchBody);
      when(() => mockRequest.headers).thenReturn({});
      when(
        () => mockDb.saveResource(any()),
      ).thenAnswer((_) async => true);

      final response = await patchResourceHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      expect(response.headers['ETag'], equals('W/"2"'));
    });

    test('Prefer: return=minimal returns 200 with no body', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'name': [
          {'family': 'OldName'},
        ],
      });
      final savedPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {
          'versionId': '2',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'NewName'},
        ],
      });

      final patchBody = jsonEncode([
        {'op': 'replace', 'path': '/name/0/family', 'value': 'NewName'},
      ]);

      var callCount = 0;
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async {
        callCount++;
        return callCount == 1 ? patient : savedPatient;
      });
      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => patchBody);
      when(() => mockRequest.headers).thenReturn({
        'prefer': 'return=minimal',
      });
      when(
        () => mockDb.saveResource(any()),
      ).thenAnswer((_) async => true);

      final response = await patchResourceHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      expect(body, isEmpty);
      expect(response.headers['ETag'], equals('W/"2"'));
    });
  });
}
