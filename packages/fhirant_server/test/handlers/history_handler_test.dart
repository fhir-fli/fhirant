import 'dart:convert';

import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:fhirant_server/src/handlers/history_handler.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

class MockRequest extends Mock implements Request {}

void main() {
  setUpAll(() {
    registerFallbackValue(fhir.R4ResourceType.Patient);
  });

  group('resourceHistoryHandler', () {
    late MockFhirAntDb mockDb;
    late MockRequest mockRequest;

    setUp(() {
      mockDb = MockFhirAntDb();
      mockRequest = MockRequest();
    });

    test('returns 200 with history bundle', () async {
      final patient1 = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {'versionId': 'v1', 'lastUpdated': '2024-01-01T00:00:00Z'},
        'name': [
          {'family': 'Original'},
        ],
      });
      final patient2 = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {'versionId': 'v2', 'lastUpdated': '2024-01-02T00:00:00Z'},
        'name': [
          {'family': 'Updated'},
        ],
      });

      when(() => mockRequest.url).thenReturn(
        Uri.parse('Patient/123/_history'),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse('http://localhost:8080/Patient/123/_history'),
      );
      when(
        () => mockDb.getResourceHistory(
          fhir.R4ResourceType.Patient,
          '123',
          since: any(named: 'since'),
        ),
      ).thenAnswer((_) async => [patient2, patient1]);

      final response = await resourceHistoryHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('Bundle'));
      expect(json['type'], equals('history'));
      expect((json['entry'] as List).length, equals(2));
    });

    test('returns 404 when no history', () async {
      when(() => mockRequest.url).thenReturn(
        Uri.parse('Patient/123/_history'),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse('http://localhost:8080/Patient/123/_history'),
      );
      when(
        () => mockDb.getResourceHistory(
          fhir.R4ResourceType.Patient,
          '123',
          since: any(named: 'since'),
        ),
      ).thenAnswer((_) async => []);

      final response = await resourceHistoryHandler(
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

    test('returns 400 for invalid type', () async {
      final response = await resourceHistoryHandler(
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

    test('respects pagination params', () async {
      final patients = List.generate(
        5,
        (i) => fhir.Patient.fromJson({
          'resourceType': 'Patient',
          'id': '123',
          'meta': {
            'versionId': 'v${i + 1}',
            'lastUpdated': '2024-01-0${i + 1}T00:00:00Z',
          },
          'name': [
            {'family': 'Version${i + 1}'},
          ],
        }),
      );

      when(() => mockRequest.url).thenReturn(
        Uri.parse('Patient/123/_history?_count=2&_offset=1'),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse('http://localhost:8080/Patient/123/_history?_count=2&_offset=1'),
      );
      when(
        () => mockDb.getResourceHistory(
          fhir.R4ResourceType.Patient,
          '123',
          since: any(named: 'since'),
        ),
      ).thenAnswer((_) async => patients);

      final response = await resourceHistoryHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('Bundle'));
      expect(json['type'], equals('history'));
      // Paginated: skip 1, take 2
      expect((json['entry'] as List).length, equals(2));
      // Total should reflect all history entries
      expect(json['total'], equals(5));
    });

    test('_since filters history entries', () async {
      final patient1 = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {'versionId': 'v2', 'lastUpdated': '2024-06-01T00:00:00Z'},
        'name': [
          {'family': 'Recent'},
        ],
      });

      when(() => mockRequest.url).thenReturn(
        Uri.parse('Patient/123/_history?_since=2024-03-01T00:00:00Z'),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient/123/_history?_since=2024-03-01T00:00:00Z',
        ),
      );
      when(
        () => mockDb.getResourceHistory(
          fhir.R4ResourceType.Patient,
          '123',
          since: any(named: 'since'),
        ),
      ).thenAnswer((_) async => [patient1]);

      final response = await resourceHistoryHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect((json['entry'] as List).length, equals(1));

      // Verify _since was passed to the DB method
      final captured = verify(
        () => mockDb.getResourceHistory(
          fhir.R4ResourceType.Patient,
          '123',
          since: captureAny(named: 'since'),
        ),
      ).captured;
      expect(captured.single, isA<DateTime>());
    });
  });

  group('typeHistoryHandler', () {
    late MockFhirAntDb mockDb;
    late MockRequest mockRequest;

    setUp(() {
      mockDb = MockFhirAntDb();
      mockRequest = MockRequest();
    });

    test('returns 200 with type-level history', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '456',
        'meta': {'versionId': 'v1', 'lastUpdated': '2024-01-01T00:00:00Z'},
        'name': [
          {'family': 'Smith'},
        ],
      });
      final patientV2 = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '456',
        'meta': {'versionId': 'v2', 'lastUpdated': '2024-01-02T00:00:00Z'},
        'name': [
          {'family': 'SmithUpdated'},
        ],
      });

      when(() => mockRequest.url).thenReturn(
        Uri.parse('Patient/_history'),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse('http://localhost:8080/Patient/_history'),
      );
      when(
        () => mockDb.getTypeHistory(
          fhir.R4ResourceType.Patient,
          since: any(named: 'since'),
        ),
      ).thenAnswer((_) async => [patientV2, patient]);

      final response = await typeHistoryHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('Bundle'));
      expect(json['type'], equals('history'));
      expect((json['entry'] as List).length, equals(2));
    });

    test('returns 400 for invalid type', () async {
      final response = await typeHistoryHandler(
        mockRequest,
        'InvalidType',
        mockDb,
      );

      expect(response.statusCode, equals(400));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('OperationOutcome'));
    });

    test('_since filters type-level history', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '456',
        'meta': {'versionId': 'v2', 'lastUpdated': '2024-06-01T00:00:00Z'},
        'name': [
          {'family': 'Recent'},
        ],
      });

      when(() => mockRequest.url).thenReturn(
        Uri.parse('Patient/_history?_since=2024-03-01T00:00:00Z'),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient/_history?_since=2024-03-01T00:00:00Z',
        ),
      );
      when(
        () => mockDb.getTypeHistory(
          fhir.R4ResourceType.Patient,
          since: any(named: 'since'),
        ),
      ).thenAnswer((_) async => [patient]);

      final response = await typeHistoryHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect((json['entry'] as List).length, equals(1));

      final captured = verify(
        () => mockDb.getTypeHistory(
          fhir.R4ResourceType.Patient,
          since: captureAny(named: 'since'),
        ),
      ).captured;
      expect(captured.single, isA<DateTime>());
    });
  });

  group('systemHistoryHandler', () {
    late MockFhirAntDb mockDb;
    late MockRequest mockRequest;

    setUp(() {
      mockDb = MockFhirAntDb();
      mockRequest = MockRequest();
    });

    test('returns 200 with system history', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '789',
        'meta': {'versionId': 'v1', 'lastUpdated': '2024-01-01T00:00:00Z'},
        'name': [
          {'family': 'Jones'},
        ],
      });
      final patientV2 = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '789',
        'meta': {'versionId': 'v2', 'lastUpdated': '2024-01-02T00:00:00Z'},
        'name': [
          {'family': 'JonesUpdated'},
        ],
      });

      when(() => mockRequest.url).thenReturn(
        Uri.parse('_history'),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse('http://localhost:8080/_history'),
      );
      when(
        () => mockDb.getSystemHistory(since: any(named: 'since')),
      ).thenAnswer((_) async => [patientV2, patient]);

      final response = await systemHistoryHandler(
        mockRequest,
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('Bundle'));
      expect(json['type'], equals('history'));
      expect((json['entry'] as List).length, equals(2));
    });

    test('returns 200 empty when no resources', () async {
      when(() => mockRequest.url).thenReturn(
        Uri.parse('_history'),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse('http://localhost:8080/_history'),
      );
      when(
        () => mockDb.getSystemHistory(since: any(named: 'since')),
      ).thenAnswer((_) async => []);

      final response = await systemHistoryHandler(
        mockRequest,
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('Bundle'));
      expect(json['type'], equals('history'));
      expect(json['total'], equals(0));
    });

    test('_since filters system-level history', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '789',
        'meta': {'versionId': 'v2', 'lastUpdated': '2024-06-01T00:00:00Z'},
        'name': [
          {'family': 'Recent'},
        ],
      });

      when(() => mockRequest.url).thenReturn(
        Uri.parse('_history?_since=2024-03-01T00:00:00Z'),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse('http://localhost:8080/_history?_since=2024-03-01T00:00:00Z'),
      );
      when(
        () => mockDb.getSystemHistory(since: any(named: 'since')),
      ).thenAnswer((_) async => [patient]);

      final response = await systemHistoryHandler(
        mockRequest,
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect((json['entry'] as List).length, equals(1));

      final captured = verify(
        () => mockDb.getSystemHistory(since: captureAny(named: 'since')),
      ).captured;
      expect(captured.single, isA<DateTime>());
    });
  });

  group('vreadResourceHandler', () {
    late MockFhirAntDb mockDb;
    late MockRequest mockRequest;

    setUp(() {
      mockDb = MockFhirAntDb();
      mockRequest = MockRequest();
    });

    test('returns 200 with specific version', () async {
      final patient1 = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {'versionId': 'v1', 'lastUpdated': '2024-01-01T00:00:00Z'},
        'name': [
          {'family': 'Original'},
        ],
      });
      final patient2 = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {'versionId': 'v2', 'lastUpdated': '2024-01-02T00:00:00Z'},
        'name': [
          {'family': 'Updated'},
        ],
      });

      when(
        () => mockDb.getResourceHistory(
          fhir.R4ResourceType.Patient,
          '123',
          since: any(named: 'since'),
        ),
      ).thenAnswer((_) async => [patient2, patient1]);

      final response = await vreadResourceHandler(
        mockRequest,
        'Patient',
        '123',
        'v1',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('Patient'));
      final names = json['name'] as List;
      expect(names[0]['family'], equals('Original'));
    });

    test('returns 404 when resource not found', () async {
      when(
        () => mockDb.getResourceHistory(
          fhir.R4ResourceType.Patient,
          '123',
          since: any(named: 'since'),
        ),
      ).thenAnswer((_) async => []);

      final response = await vreadResourceHandler(
        mockRequest,
        'Patient',
        '123',
        'v1',
        mockDb,
      );

      expect(response.statusCode, equals(404));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['error'], equals('Resource not found'));
    });

    test('returns 404 when version not found', () async {
      final patient1 = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {'versionId': 'v1', 'lastUpdated': '2024-01-01T00:00:00Z'},
        'name': [
          {'family': 'Original'},
        ],
      });

      when(
        () => mockDb.getResourceHistory(
          fhir.R4ResourceType.Patient,
          '123',
          since: any(named: 'since'),
        ),
      ).thenAnswer((_) async => [patient1]);

      final response = await vreadResourceHandler(
        mockRequest,
        'Patient',
        '123',
        'v99',
        mockDb,
      );

      expect(response.statusCode, equals(404));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['error'], equals('Version not found'));
    });

    test('returns 400 for invalid type', () async {
      final response = await vreadResourceHandler(
        mockRequest,
        'InvalidType',
        '123',
        'v1',
        mockDb,
      );

      expect(response.statusCode, equals(400));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('OperationOutcome'));
    });
  });
}
