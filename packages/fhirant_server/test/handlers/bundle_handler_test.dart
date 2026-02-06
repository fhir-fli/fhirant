import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:fhirant_server/src/handlers/bundle_handler.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

class MockRequest extends Mock implements Request {}

void main() {
  setUpAll(() {
    registerFallbackValue(fhir.R4ResourceType.Patient);
    registerFallbackValue(fhir.Patient());
  });

  group('bundleHandler - transaction', () {
    late MockFhirAntDb mockDb;
    late MockRequest mockRequest;

    setUp(() {
      mockDb = MockFhirAntDb();
      mockRequest = MockRequest();
    });

    test('processes transaction with POST entry', () async {
      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'transaction',
        'entry': [
          {
            'resource': {
              'resourceType': 'Patient',
              'name': [
                {'family': 'Test'},
              ],
            },
            'request': {'method': 'POST', 'url': 'Patient'},
          },
        ],
      });

      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => bundleJson);
      when(
        () => mockRequest.requestedUri,
      ).thenReturn(Uri.parse('http://localhost:8080/'));
      when(
        () => mockDb.saveResource(any()),
      ).thenAnswer((_) async => true);

      final response = await bundleHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('Bundle'));
      expect(json['type'], equals('transaction-response'));
      expect((json['entry'] as List).length, equals(1));
    });

    test('processes transaction with GET entry', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'name': [
          {'family': 'Found'},
        ],
      });

      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'transaction',
        'entry': [
          {
            'request': {'method': 'GET', 'url': 'Patient/123'},
          },
        ],
      });

      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => bundleJson);
      when(
        () => mockRequest.requestedUri,
      ).thenReturn(Uri.parse('http://localhost:8080/'));
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => patient);

      final response = await bundleHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('Bundle'));
      expect(json['type'], equals('transaction-response'));
      final entries = json['entry'] as List;
      expect(entries.length, equals(1));
    });

    test('returns 400 for entry missing request', () async {
      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'transaction',
        'entry': [
          {
            'resource': {
              'resourceType': 'Patient',
              'name': [
                {'family': 'Test'},
              ],
            },
          },
        ],
      });

      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => bundleJson);
      when(
        () => mockRequest.requestedUri,
      ).thenReturn(Uri.parse('http://localhost:8080/'));

      final response = await bundleHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(400));
    });

    test('returns 400 for invalid resource type in entry', () async {
      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'transaction',
        'entry': [
          {
            'resource': {
              'resourceType': 'Patient',
              'name': [
                {'family': 'Test'},
              ],
            },
            'request': {'method': 'POST', 'url': 'InvalidType'},
          },
        ],
      });

      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => bundleJson);
      when(
        () => mockRequest.requestedUri,
      ).thenReturn(Uri.parse('http://localhost:8080/'));

      final response = await bundleHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(400));
    });

    test('returns 400 for non-transaction/batch bundle type', () async {
      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'collection',
        'entry': [
          {
            'resource': {
              'resourceType': 'Patient',
              'name': [
                {'family': 'Test'},
              ],
            },
            'request': {'method': 'POST', 'url': 'Patient'},
          },
        ],
      });

      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => bundleJson);

      final response = await bundleHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(400));
    });

    test('returns 400 for empty bundle entries', () async {
      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'transaction',
        'entry': <Map<String, dynamic>>[],
      });

      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => bundleJson);

      final response = await bundleHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(400));
    });
  });

  group('bundleHandler - batch', () {
    late MockFhirAntDb mockDb;
    late MockRequest mockRequest;

    setUp(() {
      mockDb = MockFhirAntDb();
      mockRequest = MockRequest();
    });

    test('processes valid batch', () async {
      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'batch',
        'entry': [
          {
            'resource': {
              'resourceType': 'Patient',
              'name': [
                {'family': 'BatchTest'},
              ],
            },
            'request': {'method': 'POST', 'url': 'Patient'},
          },
        ],
      });

      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => bundleJson);
      when(
        () => mockRequest.requestedUri,
      ).thenReturn(Uri.parse('http://localhost:8080/'));
      when(
        () => mockDb.saveResource(any()),
      ).thenAnswer((_) async => true);

      final response = await bundleHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('Bundle'));
      expect(json['type'], equals('batch-response'));
      expect((json['entry'] as List).length, equals(1));
    });

    test('batch continues after individual entry failure', () async {
      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'batch',
        'entry': [
          {
            'resource': {
              'resourceType': 'Patient',
              'name': [
                {'family': 'GoodEntry'},
              ],
            },
            'request': {'method': 'POST', 'url': 'Patient'},
          },
          {
            'resource': {
              'resourceType': 'Patient',
              'name': [
                {'family': 'BadEntry'},
              ],
            },
            'request': {'method': 'POST', 'url': 'InvalidType'},
          },
        ],
      });

      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => bundleJson);
      when(
        () => mockRequest.requestedUri,
      ).thenReturn(Uri.parse('http://localhost:8080/'));
      when(
        () => mockDb.saveResource(any()),
      ).thenAnswer((_) async => true);

      final response = await bundleHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('Bundle'));
      final entries = json['entry'] as List;
      expect(entries.length, equals(2));
    });

    test('batch handles missing request gracefully', () async {
      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'batch',
        'entry': [
          {
            'resource': {
              'resourceType': 'Patient',
              'name': [
                {'family': 'NoRequest'},
              ],
            },
          },
        ],
      });

      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => bundleJson);
      when(
        () => mockRequest.requestedUri,
      ).thenReturn(Uri.parse('http://localhost:8080/'));

      final response = await bundleHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('Bundle'));
      final entries = json['entry'] as List;
      expect(entries.length, equals(1));
      // The entry should have an error response
      final entryResponse =
          entries[0]['response'] as Map<String, dynamic>;
      expect(entryResponse['status'], equals('400'));
    });
  });
}
