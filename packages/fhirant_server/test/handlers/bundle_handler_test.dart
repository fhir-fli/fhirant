import 'dart:convert';

import 'package:test/test.dart';
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
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'test-id',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Test'},
        ],
      });

      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'transaction',
        'entry': [
          {
            'resource': {
              'resourceType': 'Patient',
              'id': 'test-id',
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
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'test-id'),
      ).thenAnswer((_) async => patient);

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
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'batch-id',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'BatchTest'},
        ],
      });

      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'batch',
        'entry': [
          {
            'resource': {
              'resourceType': 'Patient',
              'id': 'batch-id',
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
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'batch-id'),
      ).thenAnswer((_) async => patient);

      final response = await bundleHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('Bundle'));
      expect(json['type'], equals('batch-response'));
      expect((json['entry'] as List).length, equals(1));
    });

    test('batch continues after individual entry failure', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'good-id',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'GoodEntry'},
        ],
      });

      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'batch',
        'entry': [
          {
            'resource': {
              'resourceType': 'Patient',
              'id': 'good-id',
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
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'good-id'),
      ).thenAnswer((_) async => patient);

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
      final entryResponse =
          entries[0]['response'] as Map<String, dynamic>;
      expect(entryResponse['status'], equals('400'));
    });
  });

  group('bundleHandler - DELETE', () {
    late MockFhirAntDb mockDb;
    late MockRequest mockRequest;

    setUp(() {
      mockDb = MockFhirAntDb();
      mockRequest = MockRequest();
    });

    test('transaction with DELETE entry succeeds', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'del-123',
        'name': [
          {'family': 'ToDelete'},
        ],
      });

      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'transaction',
        'entry': [
          {
            'request': {'method': 'DELETE', 'url': 'Patient/del-123'},
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
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'del-123'),
      ).thenAnswer((_) async => patient);
      when(
        () => mockDb.deleteResource(fhir.R4ResourceType.Patient, 'del-123'),
      ).thenAnswer((_) async => true);

      final response = await bundleHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['type'], equals('transaction-response'));
      final entries = json['entry'] as List;
      expect(entries.length, equals(1));
      expect(entries[0]['response']['status'], equals('204'));
      expect(entries[0]['resource'], isNull);
    });

    test('transaction DELETE non-existent returns 404', () async {
      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'transaction',
        'entry': [
          {
            'request': {'method': 'DELETE', 'url': 'Patient/not-found'},
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
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'not-found'),
      ).thenAnswer((_) async => null);

      final response = await bundleHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(404));
    });

    test('batch DELETE failure does not block other entries', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'exists',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Exists'},
        ],
      });

      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'batch',
        'entry': [
          {
            'request': {'method': 'GET', 'url': 'Patient/exists'},
          },
          {
            'request': {'method': 'DELETE', 'url': 'Patient/not-found'},
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
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'exists'),
      ).thenAnswer((_) async => patient);
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'not-found'),
      ).thenAnswer((_) async => null);

      final response = await bundleHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final entries = json['entry'] as List;
      expect(entries.length, equals(2));
      expect(entries[0]['response']['status'], equals('200'));
      expect(entries[1]['response']['status'], equals('404'));
    });
  });

  group('bundleHandler - PATCH', () {
    late MockFhirAntDb mockDb;
    late MockRequest mockRequest;

    setUp(() {
      mockDb = MockFhirAntDb();
      mockRequest = MockRequest();
    });

    test('transaction PATCH via Binary succeeds', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'patch-123',
        'name': [
          {'family': 'OldName'},
        ],
      });
      final patchedPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'patch-123',
        'meta': {
          'versionId': '2',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'NewName'},
        ],
      });

      // Create JSON Patch as base64
      final patchOps = jsonEncode([
        {'op': 'replace', 'path': '/name/0/family', 'value': 'NewName'},
      ]);
      final patchBase64 = base64Encode(utf8.encode(patchOps));

      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'transaction',
        'entry': [
          {
            'resource': {
              'resourceType': 'Binary',
              'contentType': 'application/json-patch+json',
              'data': patchBase64,
            },
            'request': {'method': 'PATCH', 'url': 'Patient/patch-123'},
          },
        ],
      });

      var callCount = 0;
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'patch-123'),
      ).thenAnswer((_) async {
        callCount++;
        return callCount == 1 ? patient : patchedPatient;
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
      expect(json['type'], equals('transaction-response'));
      final entries = json['entry'] as List;
      expect(entries.length, equals(1));
      expect(entries[0]['response']['status'], equals('200'));
      final resource = entries[0]['resource'] as Map<String, dynamic>;
      expect(resource['name'][0]['family'], equals('NewName'));
    });

    test('transaction PATCH non-existent returns 404', () async {
      final patchOps = jsonEncode([
        {'op': 'replace', 'path': '/name/0/family', 'value': 'NewName'},
      ]);
      final patchBase64 = base64Encode(utf8.encode(patchOps));

      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'transaction',
        'entry': [
          {
            'resource': {
              'resourceType': 'Binary',
              'contentType': 'application/json-patch+json',
              'data': patchBase64,
            },
            'request': {'method': 'PATCH', 'url': 'Patient/not-found'},
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
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'not-found'),
      ).thenAnswer((_) async => null);

      final response = await bundleHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(404));
    });

    test('PATCH that changes resource type fails', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'patch-type',
        'name': [
          {'family': 'Test'},
        ],
      });

      final patchOps = jsonEncode([
        {'op': 'replace', 'path': '/resourceType', 'value': 'Observation'},
      ]);
      final patchBase64 = base64Encode(utf8.encode(patchOps));

      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'transaction',
        'entry': [
          {
            'resource': {
              'resourceType': 'Binary',
              'contentType': 'application/json-patch+json',
              'data': patchBase64,
            },
            'request': {'method': 'PATCH', 'url': 'Patient/patch-type'},
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
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'patch-type'),
      ).thenAnswer((_) async => patient);

      final response = await bundleHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(400));
    });
  });

  group('bundleHandler - urn:uuid resolution', () {
    late MockFhirAntDb mockDb;
    late MockRequest mockRequest;

    setUp(() {
      mockDb = MockFhirAntDb();
      mockRequest = MockRequest();
    });

    test('POST creates resource, subsequent reference resolved', () async {
      final savedPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'pat-abc',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Smith'},
        ],
      });
      final savedObs = fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': 'obs-xyz',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '12345'},
          ],
        },
        'subject': {'reference': 'Patient/pat-abc'},
      });

      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'transaction',
        'entry': [
          {
            'fullUrl': 'urn:uuid:11111111-1111-1111-1111-111111111111',
            'resource': {
              'resourceType': 'Patient',
              'id': 'pat-abc',
              'name': [
                {'family': 'Smith'},
              ],
            },
            'request': {'method': 'POST', 'url': 'Patient'},
          },
          {
            'resource': {
              'resourceType': 'Observation',
              'id': 'obs-xyz',
              'status': 'final',
              'code': {
                'coding': [
                  {'system': 'http://loinc.org', 'code': '12345'},
                ],
              },
              'subject': {
                'reference':
                    'urn:uuid:11111111-1111-1111-1111-111111111111',
              },
            },
            'request': {'method': 'POST', 'url': 'Observation'},
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
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'pat-abc'),
      ).thenAnswer((_) async => savedPatient);
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Observation, 'obs-xyz'),
      ).thenAnswer((_) async => savedObs);

      final response = await bundleHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final entries = json['entry'] as List;
      expect(entries.length, equals(2));
      expect(entries[0]['response']['status'], equals('201'));
      expect(entries[1]['response']['status'], equals('201'));

      // Verify the Observation was saved with the resolved reference
      final captured = verify(
        () => mockDb.saveResource(captureAny()),
      ).captured;
      // Second save is the Observation
      final savedObsResource = captured[1] as fhir.Resource;
      final obsJson = savedObsResource.toJson();
      expect(obsJson['subject']['reference'], equals('Patient/pat-abc'));
    });

    test('multiple urn:uuid references all resolved', () async {
      final savedPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'pat-1',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'A'},
        ],
      });
      final savedEncounter = fhir.Encounter.fromJson({
        'resourceType': 'Encounter',
        'id': 'enc-1',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'status': 'finished',
        'class': {
          'system': 'http://terminology.hl7.org/CodeSystem/v3-ActCode',
          'code': 'AMB',
        },
      });
      final savedObs = fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': 'obs-1',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '12345'},
          ],
        },
        'subject': {'reference': 'Patient/pat-1'},
        'encounter': {'reference': 'Encounter/enc-1'},
      });

      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'transaction',
        'entry': [
          {
            'fullUrl': 'urn:uuid:aaaa',
            'resource': {
              'resourceType': 'Patient',
              'id': 'pat-1',
              'name': [
                {'family': 'A'},
              ],
            },
            'request': {'method': 'POST', 'url': 'Patient'},
          },
          {
            'fullUrl': 'urn:uuid:bbbb',
            'resource': {
              'resourceType': 'Encounter',
              'id': 'enc-1',
              'status': 'finished',
              'class': {
                'system':
                    'http://terminology.hl7.org/CodeSystem/v3-ActCode',
                'code': 'AMB',
              },
            },
            'request': {'method': 'POST', 'url': 'Encounter'},
          },
          {
            'resource': {
              'resourceType': 'Observation',
              'id': 'obs-1',
              'status': 'final',
              'code': {
                'coding': [
                  {'system': 'http://loinc.org', 'code': '12345'},
                ],
              },
              'subject': {'reference': 'urn:uuid:aaaa'},
              'encounter': {'reference': 'urn:uuid:bbbb'},
            },
            'request': {'method': 'POST', 'url': 'Observation'},
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
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'pat-1'),
      ).thenAnswer((_) async => savedPatient);
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Encounter, 'enc-1'),
      ).thenAnswer((_) async => savedEncounter);
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Observation, 'obs-1'),
      ).thenAnswer((_) async => savedObs);

      final response = await bundleHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final entries = json['entry'] as List;
      expect(entries.length, equals(3));

      // Verify the Observation was saved with both resolved references
      final captured = verify(
        () => mockDb.saveResource(captureAny()),
      ).captured;
      final savedObsResource = captured[2] as fhir.Resource;
      final obsJson = savedObsResource.toJson();
      expect(obsJson['subject']['reference'], equals('Patient/pat-1'));
      expect(obsJson['encounter']['reference'], equals('Encounter/enc-1'));
    });

    test('unresolvable urn:uuid in batch does not fail entire batch', () async {
      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'batch',
        'entry': [
          {
            'resource': {
              'resourceType': 'Observation',
              'id': 'obs-bad',
              'status': 'final',
              'code': {
                'coding': [
                  {'system': 'http://loinc.org', 'code': '12345'},
                ],
              },
              'subject': {
                'reference': 'urn:uuid:nonexistent',
              },
            },
            'request': {'method': 'POST', 'url': 'Observation'},
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
      when(
        () =>
            mockDb.getResource(fhir.R4ResourceType.Observation, 'obs-bad'),
      ).thenAnswer((_) async =>
          fhir.Observation.fromJson({
            'resourceType': 'Observation',
            'id': 'obs-bad',
            'meta': {
              'versionId': '1',
              'lastUpdated': '2024-01-15T10:30:00.000Z',
            },
            'status': 'final',
            'code': {
              'coding': [
                {'system': 'http://loinc.org', 'code': '12345'},
              ],
            },
            'subject': {
              'reference': 'urn:uuid:nonexistent',
            },
          }));

      final response = await bundleHandler(mockRequest, mockDb);

      // Batch should still succeed at the bundle level
      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['type'], equals('batch-response'));
      final entries = json['entry'] as List;
      expect(entries.length, equals(1));
      // The entry should succeed (unresolvable urn:uuid stays as-is,
      // it's up to the server to validate references later)
      expect(entries[0]['response']['status'], equals('201'));
    });

    test('urn:uuid in GET URL resolved to actual resourceType/id', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'pat-get',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'GetMe'},
        ],
      });

      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'transaction',
        'entry': [
          {
            'fullUrl': 'urn:uuid:get-uuid',
            'resource': {
              'resourceType': 'Patient',
              'id': 'pat-get',
              'name': [
                {'family': 'GetMe'},
              ],
            },
            'request': {'method': 'POST', 'url': 'Patient'},
          },
          {
            'request': {
              'method': 'GET',
              'url': 'Patient/pat-get',
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
      when(
        () => mockDb.saveResource(any()),
      ).thenAnswer((_) async => true);
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'pat-get'),
      ).thenAnswer((_) async => patient);

      final response = await bundleHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final entries = json['entry'] as List;
      expect(entries.length, equals(2));
      expect(entries[0]['response']['status'], equals('201'));
      expect(entries[1]['response']['status'], equals('200'));
      expect(entries[1]['resource']['id'], equals('pat-get'));
    });
  });

  group('bundleHandler - rollback', () {
    late MockFhirAntDb mockDb;
    late MockRequest mockRequest;

    setUp(() {
      mockDb = MockFhirAntDb();
      mockRequest = MockRequest();
    });

    test('rollback after POST calls deleteResource', () async {
      final savedPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'rb-post',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'RollbackPost'},
        ],
      });

      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'transaction',
        'entry': [
          {
            'resource': {
              'resourceType': 'Patient',
              'id': 'rb-post',
              'name': [
                {'family': 'RollbackPost'},
              ],
            },
            'request': {'method': 'POST', 'url': 'Patient'},
          },
          {
            'request': {'method': 'GET', 'url': 'Patient/not-found'},
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
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'rb-post'),
      ).thenAnswer((_) async => savedPatient);
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'not-found'),
      ).thenAnswer((_) async => null);
      when(
        () => mockDb.deleteResource(
            fhir.R4ResourceType.Patient, 'rb-post'),
      ).thenAnswer((_) async => true);

      final response = await bundleHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(404));
      verify(
        () => mockDb.deleteResource(fhir.R4ResourceType.Patient, 'rb-post'),
      ).called(1);
    });

    test('rollback after PUT restores previous version', () async {
      final originalPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'rb-put',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Original'},
        ],
      });
      final updatedPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'rb-put',
        'meta': {
          'versionId': '2',
          'lastUpdated': '2024-01-15T11:30:00.000Z',
        },
        'name': [
          {'family': 'Updated'},
        ],
      });

      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'transaction',
        'entry': [
          {
            'resource': {
              'resourceType': 'Patient',
              'id': 'rb-put',
              'name': [
                {'family': 'Updated'},
              ],
            },
            'request': {'method': 'PUT', 'url': 'Patient/rb-put'},
          },
          {
            'request': {'method': 'GET', 'url': 'Patient/not-found'},
          },
        ],
      });

      var getCallCount = 0;
      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => bundleJson);
      when(
        () => mockRequest.requestedUri,
      ).thenReturn(Uri.parse('http://localhost:8080/'));
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'rb-put'),
      ).thenAnswer((_) async {
        getCallCount++;
        // First call: get previous version for rollback
        // Second call: re-fetch after save
        return getCallCount == 1 ? originalPatient : updatedPatient;
      });
      when(
        () => mockDb.saveResource(any()),
      ).thenAnswer((_) async => true);
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'not-found'),
      ).thenAnswer((_) async => null);

      final response = await bundleHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(404));
      // Rollback should save back the original resource
      // First save: the PUT update; second save: the rollback
      final saves = verify(
        () => mockDb.saveResource(captureAny()),
      ).captured;
      expect(saves.length, equals(2));
      final rolledBack = saves[1] as fhir.Resource;
      expect(rolledBack.toJson()['name'][0]['family'], equals('Original'));
    });

    test('rollback after DELETE re-saves deleted resource', () async {
      final deletedPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'rb-del',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Deleted'},
        ],
      });

      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'transaction',
        'entry': [
          {
            'request': {'method': 'DELETE', 'url': 'Patient/rb-del'},
          },
          {
            'request': {'method': 'GET', 'url': 'Patient/not-found'},
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
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'rb-del'),
      ).thenAnswer((_) async => deletedPatient);
      when(
        () => mockDb.deleteResource(
            fhir.R4ResourceType.Patient, 'rb-del'),
      ).thenAnswer((_) async => true);
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'not-found'),
      ).thenAnswer((_) async => null);
      when(
        () => mockDb.saveResource(any()),
      ).thenAnswer((_) async => true);

      final response = await bundleHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(404));
      // Rollback should re-save the deleted resource
      final saved = verify(
        () => mockDb.saveResource(captureAny()),
      ).captured;
      expect(saved.length, equals(1));
      final resaved = saved[0] as fhir.Resource;
      expect(resaved.toJson()['name'][0]['family'], equals('Deleted'));
    });
  });

  group('bundleHandler - response enrichment', () {
    late MockFhirAntDb mockDb;
    late MockRequest mockRequest;

    setUp(() {
      mockDb = MockFhirAntDb();
      mockRequest = MockRequest();
    });

    test('POST entry response includes etag and lastModified', () async {
      final savedPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'enrich-1',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Enriched'},
        ],
      });

      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'transaction',
        'entry': [
          {
            'resource': {
              'resourceType': 'Patient',
              'id': 'enrich-1',
              'name': [
                {'family': 'Enriched'},
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
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'enrich-1'),
      ).thenAnswer((_) async => savedPatient);

      final response = await bundleHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final entries = json['entry'] as List;
      final entryResponse =
          entries[0]['response'] as Map<String, dynamic>;
      expect(entryResponse['status'], equals('201'));
      expect(entryResponse['etag'], equals('W/"1"'));
      expect(entryResponse['lastModified'], isNotNull);
    });

    test('PUT entry response includes updated etag', () async {
      final existingPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'enrich-2',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Old'},
        ],
      });
      final updatedPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'enrich-2',
        'meta': {
          'versionId': '2',
          'lastUpdated': '2024-01-15T11:30:00.000Z',
        },
        'name': [
          {'family': 'New'},
        ],
      });

      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'transaction',
        'entry': [
          {
            'resource': {
              'resourceType': 'Patient',
              'id': 'enrich-2',
              'name': [
                {'family': 'New'},
              ],
            },
            'request': {'method': 'PUT', 'url': 'Patient/enrich-2'},
          },
        ],
      });

      var getCallCount = 0;
      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => bundleJson);
      when(
        () => mockRequest.requestedUri,
      ).thenReturn(Uri.parse('http://localhost:8080/'));
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'enrich-2'),
      ).thenAnswer((_) async {
        getCallCount++;
        return getCallCount == 1 ? existingPatient : updatedPatient;
      });
      when(
        () => mockDb.saveResource(any()),
      ).thenAnswer((_) async => true);

      final response = await bundleHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final entries = json['entry'] as List;
      final entryResponse =
          entries[0]['response'] as Map<String, dynamic>;
      expect(entryResponse['status'], equals('200'));
      expect(entryResponse['etag'], equals('W/"2"'));
    });
  });

  group('bundleHandler - conditional operations', () {
    late MockFhirAntDb mockDb;
    late MockRequest mockRequest;

    setUp(() {
      mockDb = MockFhirAntDb();
      mockRequest = MockRequest();
    });

    test('POST with ifNoneExist returns existing (200)', () async {
      final existingPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'cond-1',
        'meta': {
          'versionId': '1',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Existing'},
        ],
        'identifier': [
          {'system': 'http://example.com', 'value': 'MRN123'},
        ],
      });

      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'transaction',
        'entry': [
          {
            'resource': {
              'resourceType': 'Patient',
              'name': [
                {'family': 'Existing'},
              ],
              'identifier': [
                {'system': 'http://example.com', 'value': 'MRN123'},
              ],
            },
            'request': {
              'method': 'POST',
              'url': 'Patient',
              'ifNoneExist': 'identifier=MRN123',
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
      when(
        () => mockDb.search(
              resourceType: fhir.R4ResourceType.Patient,
              searchParameters: any(named: 'searchParameters'),
            ),
      ).thenAnswer((_) async => [existingPatient]);

      final response = await bundleHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final entries = json['entry'] as List;
      expect(entries[0]['response']['status'], equals('200'));
      // saveResource should NOT have been called
      verifyNever(() => mockDb.saveResource(any()));
    });

    test('PUT with ifMatch version mismatch fails transaction', () async {
      final existingPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'cond-2',
        'meta': {
          'versionId': '3',
          'lastUpdated': '2024-01-15T10:30:00.000Z',
        },
        'name': [
          {'family': 'Existing'},
        ],
      });

      final bundleJson = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'transaction',
        'entry': [
          {
            'resource': {
              'resourceType': 'Patient',
              'id': 'cond-2',
              'name': [
                {'family': 'Updated'},
              ],
            },
            'request': {
              'method': 'PUT',
              'url': 'Patient/cond-2',
              'ifMatch': 'W/"1"',
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
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, 'cond-2'),
      ).thenAnswer((_) async => existingPatient);

      final response = await bundleHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(412));
      // saveResource should NOT have been called
      verifyNever(() => mockDb.saveResource(any()));
    });
  });
}
