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
  });

  group('getResourceByIdHandler', () {
    late MockFhirAntDb mockDb;
    late MockRequest mockRequest;

    setUp(() {
      mockDb = MockFhirAntDb();
      mockRequest = MockRequest();
      when(() => mockRequest.context).thenReturn({});
    });

    test('returns 200 with resource when found', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'name': [
          {'family': 'Smith'},
        ],
      });

      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => patient);
      when(() => mockRequest.url).thenReturn(
        Uri.parse('Patient/123'),
      );
      when(() => mockRequest.headers).thenReturn({});

      final response = await getResourceByIdHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('Patient'));
      expect(json['id'], equals('123'));
      verify(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).called(1);
    });

    test('returns 404 when not found', () async {
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => null);

      final response = await getResourceByIdHandler(
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
      final response = await getResourceByIdHandler(
        mockRequest,
        'InvalidType',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(400));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('OperationOutcome'));
      verifyNever(() => mockDb.getResource(any(), any()));
    });

    test('returns 500 when database throws', () async {
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenThrow(Exception('Database error'));

      final response = await getResourceByIdHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(500));
    });

    test('returns ETag header', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {
          'versionId': '42',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Smith'},
        ],
      });

      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => patient);
      when(() => mockRequest.url).thenReturn(
        Uri.parse('Patient/123'),
      );
      when(() => mockRequest.headers).thenReturn({});

      final response = await getResourceByIdHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      expect(response.headers['ETag'], equals('W/"42"'));
    });

    test('returns Last-Modified header', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {
          'versionId': '42',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Smith'},
        ],
      });

      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => patient);
      when(() => mockRequest.url).thenReturn(
        Uri.parse('Patient/123'),
      );
      when(() => mockRequest.headers).thenReturn({});

      final response = await getResourceByIdHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      expect(response.headers.containsKey('Last-Modified'), isTrue);
    });

    test('If-None-Match matching returns 304', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {
          'versionId': '42',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Smith'},
        ],
      });

      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => patient);
      when(() => mockRequest.url).thenReturn(
        Uri.parse('Patient/123'),
      );
      when(() => mockRequest.headers).thenReturn({
        'if-none-match': 'W/"42"',
      });

      final response = await getResourceByIdHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(304));
    });

    test('If-None-Match non-matching returns 200', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {
          'versionId': '42',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Smith'},
        ],
      });

      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => patient);
      when(() => mockRequest.url).thenReturn(
        Uri.parse('Patient/123'),
      );
      when(() => mockRequest.headers).thenReturn({
        'if-none-match': 'W/"99"',
      });

      final response = await getResourceByIdHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(200));
    });

    test('read with _summary=text returns only narrative fields', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'text': {
          'status': 'generated',
          'div': '<div xmlns="http://www.w3.org/1999/xhtml">Test</div>',
        },
        'name': [
          {'family': 'Smith'},
        ],
      });

      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => patient);
      when(() => mockRequest.url).thenReturn(
        Uri.parse('Patient/123?_summary=text'),
      );
      when(() => mockRequest.headers).thenReturn({});

      final response = await getResourceByIdHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json.containsKey('id'), isTrue);
      expect(json.containsKey('text'), isTrue);
      expect(json.containsKey('name'), isFalse);
    });

    test('If-Modified-Since when not modified returns 304', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {
          'versionId': '42',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Smith'},
        ],
      });

      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => patient);
      when(() => mockRequest.url).thenReturn(
        Uri.parse('Patient/123'),
      );
      when(() => mockRequest.headers).thenReturn({
        // Resource was last updated 2024-01-15; If-Modified-Since is later
        'if-modified-since': 'Wed, 17 Jan 2024 00:00:00 GMT',
      });

      final response = await getResourceByIdHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(304));
    });

    test('If-Modified-Since when modified returns 200', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {
          'versionId': '42',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Smith'},
        ],
      });

      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => patient);
      when(() => mockRequest.url).thenReturn(
        Uri.parse('Patient/123'),
      );
      when(() => mockRequest.headers).thenReturn({
        // Resource was last updated 2024-01-15; If-Modified-Since is earlier
        'if-modified-since': 'Sat, 13 Jan 2024 00:00:00 GMT',
      });

      final response = await getResourceByIdHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(200));
    });

    test('If-Modified-Since malformed header is ignored', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {
          'versionId': '42',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Smith'},
        ],
      });

      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => patient);
      when(() => mockRequest.url).thenReturn(
        Uri.parse('Patient/123'),
      );
      when(() => mockRequest.headers).thenReturn({
        'if-modified-since': 'not-a-valid-date',
      });

      final response = await getResourceByIdHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(200));
    });

    test('read with _elements=name returns subset', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Smith'},
        ],
        'gender': 'male',
      });

      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => patient);
      when(() => mockRequest.url).thenReturn(
        Uri.parse('Patient/123?_elements=name'),
      );
      when(() => mockRequest.headers).thenReturn({});

      final response = await getResourceByIdHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json.containsKey('name'), isTrue);
      expect(json.containsKey('gender'), isFalse);
      final security =
          (json['meta'] as Map)['security'] as List;
      expect(security.any((t) => t['code'] == 'SUBSETTED'), isTrue);
    });

    test('patient scope allows read of own Patient resource', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'pat-1',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Smith'},
        ],
      });

      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'pat-1'),
      ).thenAnswer((_) async => patient);
      when(() => mockRequest.url).thenReturn(
        Uri.parse('Patient/pat-1'),
      );
      when(() => mockRequest.headers).thenReturn({});
      when(() => mockRequest.context).thenReturn({
        'auth_user': {
          'scopes': ['patient/Patient.r'],
          'patientId': 'pat-1',
        },
      });

      final response = await getResourceByIdHandler(
        mockRequest,
        'Patient',
        'pat-1',
        mockDb,
      );

      expect(response.statusCode, equals(200));
    });

    test('patient scope denies read of other Patient resource', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'pat-2',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Jones'},
        ],
      });

      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'pat-2'),
      ).thenAnswer((_) async => patient);
      when(() => mockRequest.url).thenReturn(
        Uri.parse('Patient/pat-2'),
      );
      when(() => mockRequest.headers).thenReturn({});
      when(() => mockRequest.context).thenReturn({
        'auth_user': {
          'scopes': ['patient/Patient.r'],
          'patientId': 'pat-1',
        },
      });

      final response = await getResourceByIdHandler(
        mockRequest,
        'Patient',
        'pat-2',
        mockDb,
      );

      expect(response.statusCode, equals(403));
    });

    test('patient scope allows Observation in compartment', () async {
      final obs = fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': 'obs-1',
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '1234-5'}
          ]
        },
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
      });

      when(
        () => mockDb.getResource(fhir.R4ResourceType.Observation, 'obs-1'),
      ).thenAnswer((_) async => obs);
      when(() => mockRequest.url).thenReturn(
        Uri.parse('Observation/obs-1'),
      );
      when(() => mockRequest.headers).thenReturn({});
      when(() => mockRequest.context).thenReturn({
        'auth_user': {
          'scopes': ['patient/Observation.r'],
          'patientId': 'pat-1',
        },
      });
      when(() => mockDb.getCompartmentResourceIds(
            compartmentType: 'Patient',
            compartmentId: 'pat-1',
            compartmentDefinition: any(named: 'compartmentDefinition'),
            typeFilter: any(named: 'typeFilter'),
            since: any(named: 'since'),
          )).thenAnswer((_) async => {
            'Observation': {'obs-1'},
          });

      final response = await getResourceByIdHandler(
        mockRequest,
        'Observation',
        'obs-1',
        mockDb,
      );

      expect(response.statusCode, equals(200));
    });

    test('patient scope denies Observation not in compartment', () async {
      final obs = fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': 'obs-other',
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '1234-5'}
          ]
        },
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
      });

      when(
        () => mockDb.getResource(fhir.R4ResourceType.Observation, 'obs-other'),
      ).thenAnswer((_) async => obs);
      when(() => mockRequest.url).thenReturn(
        Uri.parse('Observation/obs-other'),
      );
      when(() => mockRequest.headers).thenReturn({});
      when(() => mockRequest.context).thenReturn({
        'auth_user': {
          'scopes': ['patient/Observation.r'],
          'patientId': 'pat-1',
        },
      });
      when(() => mockDb.getCompartmentResourceIds(
            compartmentType: 'Patient',
            compartmentId: 'pat-1',
            compartmentDefinition: any(named: 'compartmentDefinition'),
            typeFilter: any(named: 'typeFilter'),
            since: any(named: 'since'),
          )).thenAnswer((_) async => {
            'Observation': <String>{},
          });

      final response = await getResourceByIdHandler(
        mockRequest,
        'Observation',
        'obs-other',
        mockDb,
      );

      expect(response.statusCode, equals(403));
    });

    test('_summary=true returns isSummary fields for Patient', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Smith'},
        ],
        'gender': 'male',
        'birthDate': '1990-01-01',
        'text': {
          'status': 'generated',
          'div': '<div xmlns="http://www.w3.org/1999/xhtml">Test</div>',
        },
        'generalPractitioner': [
          {'reference': 'Practitioner/prac-1'}
        ],
        'contact': [
          {
            'name': {'family': 'ContactPerson'}
          }
        ],
        'extension': [
          {
            'url': 'http://example.com/ext',
            'valueString': 'extra',
          }
        ],
      });

      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => patient);
      when(() => mockRequest.url).thenReturn(
        Uri.parse('Patient/123?_summary=true'),
      );
      when(() => mockRequest.headers).thenReturn({});

      final response = await getResourceByIdHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      // Summary fields should be present
      expect(json.containsKey('name'), isTrue);
      expect(json.containsKey('gender'), isTrue);
      expect(json.containsKey('birthDate'), isTrue);
      expect(json.containsKey('contact'), isTrue);
      expect(json.containsKey('generalPractitioner'), isTrue);
      // Non-summary fields should be absent
      expect(json.containsKey('text'), isFalse);
      expect(json.containsKey('extension'), isFalse);
      // SUBSETTED tag should be present
      final security =
          (json['meta'] as Map)['security'] as List;
      expect(security.any((t) => t['code'] == 'SUBSETTED'), isTrue);
    });
  });
}
