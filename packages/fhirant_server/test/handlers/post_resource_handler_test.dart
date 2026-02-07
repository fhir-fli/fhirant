import 'dart:convert';

import 'package:test/test.dart';
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

  group('postResourceHandler', () {
    late MockFhirAntDb mockDb;
    late MockRequest mockRequest;

    setUp(() {
      mockDb = MockFhirAntDb();
      mockRequest = MockRequest();
    });

    test('returns 201 when resource created successfully', () async {
      final patientJson = jsonEncode({
        'resourceType': 'Patient',
        'id': 'test-123',
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
      ).thenAnswer((_) async => true);
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'test-123'),
      ).thenAnswer((_) async => null);

      final response = await postResourceHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(201));
      expect(response.headers['Location'], contains('/Patient/'));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('Patient'));
    });

    test('returns 400 when resource type in body mismatches URL', () async {
      final observationJson = jsonEncode({
        'resourceType': 'Observation',
        'id': 'obs-1',
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

      final response = await postResourceHandler(
        mockRequest,
        'Patient',
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
        'id': 'test-123',
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

      final response = await postResourceHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(500));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('OperationOutcome'));
    });

    test('returns 400 when body is invalid JSON', () async {
      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => 'not json');

      final response = await postResourceHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(400));
    });

    test('returns ETag header on successful create', () async {
      final savedPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'test-123',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Test'},
        ],
      });
      final patientJson = jsonEncode({
        'resourceType': 'Patient',
        'id': 'test-123',
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
      ).thenAnswer((_) async => true);
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'test-123'),
      ).thenAnswer((_) async => savedPatient);

      final response = await postResourceHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(201));
      expect(response.headers['ETag'], equals('W/"1"'));
    });

    test('returns Last-Modified header on successful create', () async {
      final savedPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'test-123',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Test'},
        ],
      });
      final patientJson = jsonEncode({
        'resourceType': 'Patient',
        'id': 'test-123',
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
      ).thenAnswer((_) async => true);
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'test-123'),
      ).thenAnswer((_) async => savedPatient);

      final response = await postResourceHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(201));
      expect(response.headers.containsKey('Last-Modified'), isTrue);
    });

    test('Prefer: return=minimal returns 201 with no body', () async {
      final savedPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'test-123',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Test'},
        ],
      });
      final patientJson = jsonEncode({
        'resourceType': 'Patient',
        'id': 'test-123',
        'name': [
          {'family': 'Test'},
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
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'test-123'),
      ).thenAnswer((_) async => savedPatient);

      final response = await postResourceHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(201));
      final body = await response.readAsString();
      expect(body, isEmpty);
      expect(response.headers['ETag'], equals('W/"1"'));
      expect(response.headers['Location'], contains('/Patient/'));
    });

    test('Prefer: return=OperationOutcome returns 201 with OO', () async {
      final savedPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'test-123',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Test'},
        ],
      });
      final patientJson = jsonEncode({
        'resourceType': 'Patient',
        'id': 'test-123',
        'name': [
          {'family': 'Test'},
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
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'test-123'),
      ).thenAnswer((_) async => savedPatient);

      final response = await postResourceHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(201));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('OperationOutcome'));
    });

    test('default Prefer returns full resource (representation)', () async {
      final savedPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'test-123',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Test'},
        ],
      });
      final patientJson = jsonEncode({
        'resourceType': 'Patient',
        'id': 'test-123',
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
      ).thenAnswer((_) async => true);
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'test-123'),
      ).thenAnswer((_) async => savedPatient);

      final response = await postResourceHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(201));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('Patient'));
      expect(json['id'], equals('test-123'));
    });

    test('If-None-Exist with no match creates normally', () async {
      final patientJson = jsonEncode({
        'resourceType': 'Patient',
        'id': 'test-new',
        'name': [
          {'family': 'New'},
        ],
      });

      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => patientJson);
      when(() => mockRequest.headers).thenReturn({
        'if-none-exist': 'identifier=new',
      });
      when(
        () => mockDb.search(
          resourceType: fhir.R4ResourceType.Patient,
          searchParameters: {
            'identifier': ['new'],
          },
        ),
      ).thenAnswer((_) async => []);
      when(
        () => mockDb.saveResource(any()),
      ).thenAnswer((_) async => true);
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'test-new'),
      ).thenAnswer((_) async => null);

      final response = await postResourceHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(201));
    });

    test('If-None-Exist with single match returns existing', () async {
      final existingPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'existing-1',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Existing'},
        ],
      });
      final patientJson = jsonEncode({
        'resourceType': 'Patient',
        'id': 'test-new',
        'name': [
          {'family': 'New'},
        ],
      });

      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => patientJson);
      when(() => mockRequest.headers).thenReturn({
        'if-none-exist': 'identifier=existing',
      });
      when(
        () => mockDb.search(
          resourceType: fhir.R4ResourceType.Patient,
          searchParameters: {
            'identifier': ['existing'],
          },
        ),
      ).thenAnswer((_) async => [existingPatient]);

      final response = await postResourceHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('Patient'));
      expect(json['id'], equals('existing-1'));
    });

    test('If-None-Exist with multiple matches returns 412', () async {
      final p1 = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'p1',
        'name': [
          {'family': 'Smith'},
        ],
      });
      final p2 = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'p2',
        'name': [
          {'family': 'Smith'},
        ],
      });
      final patientJson = jsonEncode({
        'resourceType': 'Patient',
        'id': 'test-new',
        'name': [
          {'family': 'Smith'},
        ],
      });

      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => patientJson);
      when(() => mockRequest.headers).thenReturn({
        'if-none-exist': 'name=Smith',
      });
      when(
        () => mockDb.search(
          resourceType: fhir.R4ResourceType.Patient,
          searchParameters: {
            'name': ['Smith'],
          },
        ),
      ).thenAnswer((_) async => [p1, p2]);

      final response = await postResourceHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(412));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('OperationOutcome'));
    });

    test('If-None-Exist with empty value proceeds normally', () async {
      final patientJson = jsonEncode({
        'resourceType': 'Patient',
        'id': 'test-123',
        'name': [
          {'family': 'Test'},
        ],
      });

      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => patientJson);
      when(() => mockRequest.headers).thenReturn({
        'if-none-exist': '',
      });
      when(
        () => mockDb.saveResource(any()),
      ).thenAnswer((_) async => true);
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'test-123'),
      ).thenAnswer((_) async => null);

      final response = await postResourceHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(201));
    });
  });
}
