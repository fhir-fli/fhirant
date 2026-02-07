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
  });
}
