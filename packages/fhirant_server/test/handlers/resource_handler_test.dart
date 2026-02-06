import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mocktail/src/mocktail.dart' show registerFallbackValue;
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:fhirant_server/src/handlers/resource_handler.dart';

// Mock classes
class MockFhirAntDb extends Mock implements FhirAntDb {}

class MockRequest extends Mock implements Request {}

void main() {
  setUpAll(() {
    // Register fallback values for mocktail
    registerFallbackValue(<String, List<String>>{});
    registerFallbackValue(<String>[]);
    registerFallbackValue(fhir.R4ResourceType.Patient);
  });

  group('deleteResourceHandler', () {
    late MockFhirAntDb mockDb;
    late MockRequest mockRequest;

    setUp(() {
      mockDb = MockFhirAntDb();
      mockRequest = MockRequest();
    });

    test('returns 204 when resource is successfully deleted', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
      });

      when(
        () => mockRequest.url,
      ).thenReturn(Uri.parse('http://localhost:8080/Patient/123'));
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => patient);
      when(
        () => mockDb.deleteResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => true);

      final response = await deleteResourceHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(204));
      verify(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).called(1);
      verify(
        () => mockDb.deleteResource(fhir.R4ResourceType.Patient, '123'),
      ).called(1);
    });

    test('returns 404 when resource does not exist', () async {
      when(
        () => mockRequest.url,
      ).thenReturn(Uri.parse('http://localhost:8080/Patient/123'));
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => null);

      final response = await deleteResourceHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(404));
      verify(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).called(1);
      verifyNever(() => mockDb.deleteResource(any(), any()));
    });

    test('returns 400 when resource type is invalid', () async {
      when(
        () => mockRequest.url,
      ).thenReturn(Uri.parse('http://localhost:8080/InvalidType/123'));

      final response = await deleteResourceHandler(
        mockRequest,
        'InvalidType',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(400));
      verifyNever(() => mockDb.getResource(any(), any()));
      verifyNever(() => mockDb.deleteResource(any(), any()));
    });

    test('returns 500 when database delete fails', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
      });

      when(
        () => mockRequest.url,
      ).thenReturn(Uri.parse('http://localhost:8080/Patient/123'));
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => patient);
      when(
        () => mockDb.deleteResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => false);

      final response = await deleteResourceHandler(
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

    test('returns 500 when database throws exception', () async {
      when(
        () => mockRequest.url,
      ).thenReturn(Uri.parse('http://localhost:8080/Patient/123'));
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenThrow(Exception('Database error'));

      final response = await deleteResourceHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(500));
    });
  });

  group('getResourcesHandler', () {
    late MockFhirAntDb mockDb;
    late MockRequest mockRequest;

    setUp(() {
      mockDb = MockFhirAntDb();
      mockRequest = MockRequest();
    });

    test('uses pagination when no search parameters provided', () async {
      final patients = [
        fhir.Patient.fromJson({
          'resourceType': 'Patient',
          'id': '1',
          'meta': {'lastUpdated': DateTime.now().toIso8601String()},
        }),
        fhir.Patient.fromJson({
          'resourceType': 'Patient',
          'id': '2',
          'meta': {'lastUpdated': DateTime.now().toIso8601String()},
        }),
      ];

      when(() => mockRequest.url).thenReturn(
        Uri.parse('http://localhost:8080/Patient?_count=10&_offset=0'),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse('http://localhost:8080/Patient?_count=10&_offset=0'),
      );
      when(
        () => mockDb.getResourcesWithPagination(
          resourceType: fhir.R4ResourceType.Patient,
          count: 10,
          offset: 0,
        ),
      ).thenAnswer((_) async => patients);
      when(
        () => mockDb.getResourceCount(fhir.R4ResourceType.Patient),
      ).thenAnswer((_) async => 2);
      final response = await getResourcesHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('Bundle'));
      expect(json['type'], equals('searchset'));
      expect((json['entry'] as List).length, equals(2));

      verify(
        () => mockDb.getResourcesWithPagination(
          resourceType: fhir.R4ResourceType.Patient,
          count: 10,
          offset: 0,
        ),
      ).called(1);
      verifyNever(
        () => mockDb.search(
          resourceType: any(named: 'resourceType'),
          searchParameters: any(named: 'searchParameters'),
          count: any(named: 'count'),
          offset: any(named: 'offset'),
          sort: any(named: 'sort'),
        ),
      );
    });

    test('uses search when search parameters are provided', () async {
      final patients = [
        fhir.Patient.fromJson({
          'resourceType': 'Patient',
          'id': '1',
          'name': [
            {'family': 'Smith'},
          ],
          'meta': {'lastUpdated': DateTime.now().toIso8601String()},
        }),
      ];

      when(() => mockRequest.url).thenReturn(
        Uri.parse('http://localhost:8080/Patient?name=Smith&_count=10'),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse('http://localhost:8080/Patient?name=Smith&_count=10'),
      );
      when(
        () => mockDb.search(
          resourceType: fhir.R4ResourceType.Patient,
          searchParameters: {
            'name': ['Smith'],
          },
          count: 10,
          offset: 0,
          sort: null,
        ),
      ).thenAnswer((_) async => patients);
      when(
        () => mockDb.searchCount(
          resourceType: fhir.R4ResourceType.Patient,
          searchParameters: {'name': ['Smith']},
        ),
      ).thenAnswer((_) async => 1);
      final response = await getResourcesHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('Bundle'));
      expect((json['entry'] as List).length, equals(1));

      verify(
        () => mockDb.search(
          resourceType: fhir.R4ResourceType.Patient,
          searchParameters: {
            'name': ['Smith'],
          },
          count: 10,
          offset: 0,
          sort: null,
        ),
      ).called(1);
      verifyNever(
        () => mockDb.getResourcesWithPagination(
          resourceType: fhir.R4ResourceType.Patient,
          count: 10,
          offset: 0,
        ),
      );
    });

    test('returns 400 for invalid resource type', () async {
      when(
        () => mockRequest.url,
      ).thenReturn(Uri.parse('http://localhost:8080/InvalidType'));

      final response = await getResourcesHandler(
        mockRequest,
        'InvalidType',
        mockDb,
      );

      expect(response.statusCode, equals(400));
      verifyNever(
        () => mockDb.getResourcesWithPagination(
          resourceType: any(named: 'resourceType'),
          count: any(named: 'count'),
          offset: any(named: 'offset'),
        ),
      );
      verifyNever(
        () => mockDb.search(
          resourceType: any(named: 'resourceType'),
          searchParameters: any(named: 'searchParameters'),
          count: any(named: 'count'),
          offset: any(named: 'offset'),
          sort: any(named: 'sort'),
        ),
      );
    });

    test('handles default count and offset values', () async {
      when(
        () => mockRequest.url,
      ).thenReturn(Uri.parse('http://localhost:8080/Patient'));
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse('http://localhost:8080/Patient'),
      );
      when(
        () => mockDb.getResourcesWithPagination(
          resourceType: fhir.R4ResourceType.Patient,
          count: 20,
          offset: 0,
        ),
      ).thenAnswer((_) async => []);
      when(
        () => mockDb.getResourceCount(fhir.R4ResourceType.Patient),
      ).thenAnswer((_) async => 0);
      final response = await getResourcesHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      verify(
        () => mockDb.getResourcesWithPagination(
          resourceType: fhir.R4ResourceType.Patient,
          count: 20,
          offset: 0,
        ),
      ).called(1);
    });
  });
}
