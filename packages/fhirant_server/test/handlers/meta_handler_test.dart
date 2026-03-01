// ignore_for_file: lines_longer_than_80_chars
import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shelf/shelf.dart';

import 'package:fhirant_server/src/handlers/meta_handler.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

class MockRequest extends Mock implements Request {}

void main() {
  late MockFhirAntDb mockDb;
  late MockRequest mockRequest;

  setUpAll(() {
    registerFallbackValue(fhir.R4ResourceType.Patient);
    registerFallbackValue(
      fhir.Patient(name: [fhir.HumanName(family: 'Fallback'.toFhirString)]),
    );
  });

  setUp(() {
    mockDb = MockFhirAntDb();
    mockRequest = MockRequest();
  });

  // ─────────────────────────────────────────────────────────────────────────
  // $meta handler
  // ─────────────────────────────────────────────────────────────────────────
  group('metaHandler', () {
    test('returns meta for existing resource', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {
          'versionId': '1',
          'tag': [
            {'system': 'http://example.com', 'code': 'test-tag'},
          ],
          'profile': ['http://example.com/StructureDefinition/myprofile'],
        },
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, '123'))
          .thenAnswer((_) async => patient);

      final response = await metaHandler(
        mockRequest, 'Patient', '123', mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['resourceType'], equals('Parameters'));
      final params = body['parameter'] as List;
      expect(params, hasLength(1));
      final returnParam = params[0] as Map<String, dynamic>;
      expect(returnParam['name'], equals('return'));
      final meta = returnParam['valueMeta'] as Map<String, dynamic>;
      expect(meta['tag'], isNotNull);
      expect((meta['tag'] as List).first['code'], equals('test-tag'));
    });

    test('returns empty meta for resource without meta', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '456',
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, '456'))
          .thenAnswer((_) async => patient);

      final response = await metaHandler(
        mockRequest, 'Patient', '456', mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['resourceType'], equals('Parameters'));
    });

    test('returns 404 for non-existent resource', () async {
      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, 'missing'))
          .thenAnswer((_) async => null);

      final response = await metaHandler(
        mockRequest, 'Patient', 'missing', mockDb,
      );

      expect(response.statusCode, equals(404));
    });

    test('returns 400 for invalid resource type', () async {
      final response = await metaHandler(
        mockRequest, 'InvalidType', '123', mockDb,
      );

      expect(response.statusCode, equals(400));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // $meta-add handler
  // ─────────────────────────────────────────────────────────────────────────
  group('metaAddHandler', () {
    test('adds tags to resource', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {
          'tag': [
            {'system': 'http://example.com', 'code': 'existing'},
          ],
        },
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, '123'))
          .thenAnswer((_) async => patient);
      when(() => mockDb.saveResource(any())).thenAnswer((_) async => true);

      final inputBody = jsonEncode({
        'resourceType': 'Parameters',
        'parameter': [
          {
            'name': 'meta',
            'valueMeta': {
              'tag': [
                {'system': 'http://example.com', 'code': 'new-tag'},
              ],
            },
          },
        ],
      });

      when(() => mockRequest.readAsString())
          .thenAnswer((_) async => inputBody);

      final response = await metaAddHandler(
        mockRequest, 'Patient', '123', mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['resourceType'], equals('Parameters'));
      final meta = (body['parameter'] as List)[0]['valueMeta'] as Map<String, dynamic>;
      final tags = meta['tag'] as List;
      expect(tags, hasLength(2));
      // Verify saveResource was called
      verify(() => mockDb.saveResource(any())).called(1);
    });

    test('deduplicates existing tags', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {
          'tag': [
            {'system': 'http://example.com', 'code': 'existing'},
          ],
        },
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, '123'))
          .thenAnswer((_) async => patient);
      when(() => mockDb.saveResource(any())).thenAnswer((_) async => true);

      final inputBody = jsonEncode({
        'resourceType': 'Parameters',
        'parameter': [
          {
            'name': 'meta',
            'valueMeta': {
              'tag': [
                {'system': 'http://example.com', 'code': 'existing'},
              ],
            },
          },
        ],
      });

      when(() => mockRequest.readAsString())
          .thenAnswer((_) async => inputBody);

      final response = await metaAddHandler(
        mockRequest, 'Patient', '123', mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final meta = (body['parameter'] as List)[0]['valueMeta'] as Map<String, dynamic>;
      final tags = meta['tag'] as List;
      // Should still be 1 tag (not duplicated)
      expect(tags, hasLength(1));
    });

    test('adds profiles and security labels', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, '123'))
          .thenAnswer((_) async => patient);
      when(() => mockDb.saveResource(any())).thenAnswer((_) async => true);

      final inputBody = jsonEncode({
        'resourceType': 'Parameters',
        'parameter': [
          {
            'name': 'meta',
            'valueMeta': {
              'profile': ['http://example.com/StructureDefinition/myprofile'],
              'security': [
                {'system': 'http://terminology.hl7.org/CodeSystem/v3-Confidentiality', 'code': 'R'},
              ],
            },
          },
        ],
      });

      when(() => mockRequest.readAsString())
          .thenAnswer((_) async => inputBody);

      final response = await metaAddHandler(
        mockRequest, 'Patient', '123', mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final meta = (body['parameter'] as List)[0]['valueMeta'] as Map<String, dynamic>;
      expect(meta['profile'], isNotNull);
      expect(meta['security'], isNotNull);
    });

    test('returns 404 for non-existent resource', () async {
      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, 'missing'))
          .thenAnswer((_) async => null);

      final response = await metaAddHandler(
        mockRequest, 'Patient', 'missing', mockDb,
      );

      expect(response.statusCode, equals(404));
    });

    test('returns 400 for invalid request body', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, '123'))
          .thenAnswer((_) async => patient);

      when(() => mockRequest.readAsString())
          .thenAnswer((_) async => '{"not": "a parameters resource"}');

      final response = await metaAddHandler(
        mockRequest, 'Patient', '123', mockDb,
      );

      expect(response.statusCode, equals(400));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // $meta-delete handler
  // ─────────────────────────────────────────────────────────────────────────
  group('metaDeleteHandler', () {
    test('removes tags from resource', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {
          'tag': [
            {'system': 'http://example.com', 'code': 'keep'},
            {'system': 'http://example.com', 'code': 'remove'},
          ],
        },
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, '123'))
          .thenAnswer((_) async => patient);
      when(() => mockDb.saveResource(any())).thenAnswer((_) async => true);

      final inputBody = jsonEncode({
        'resourceType': 'Parameters',
        'parameter': [
          {
            'name': 'meta',
            'valueMeta': {
              'tag': [
                {'system': 'http://example.com', 'code': 'remove'},
              ],
            },
          },
        ],
      });

      when(() => mockRequest.readAsString())
          .thenAnswer((_) async => inputBody);

      final response = await metaDeleteHandler(
        mockRequest, 'Patient', '123', mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final meta = (body['parameter'] as List)[0]['valueMeta'] as Map<String, dynamic>;
      final tags = meta['tag'] as List;
      expect(tags, hasLength(1));
      expect(tags[0]['code'], equals('keep'));
      verify(() => mockDb.saveResource(any())).called(1);
    });

    test('removes profiles from resource', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {
          'profile': [
            'http://example.com/profile/a',
            'http://example.com/profile/b',
          ],
        },
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, '123'))
          .thenAnswer((_) async => patient);
      when(() => mockDb.saveResource(any())).thenAnswer((_) async => true);

      final inputBody = jsonEncode({
        'resourceType': 'Parameters',
        'parameter': [
          {
            'name': 'meta',
            'valueMeta': {
              'profile': ['http://example.com/profile/a'],
            },
          },
        ],
      });

      when(() => mockRequest.readAsString())
          .thenAnswer((_) async => inputBody);

      final response = await metaDeleteHandler(
        mockRequest, 'Patient', '123', mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final meta = (body['parameter'] as List)[0]['valueMeta'] as Map<String, dynamic>;
      final profiles = meta['profile'] as List;
      expect(profiles, hasLength(1));
      expect(profiles[0], equals('http://example.com/profile/b'));
    });

    test('returns 404 for non-existent resource', () async {
      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, 'missing'))
          .thenAnswer((_) async => null);

      final response = await metaDeleteHandler(
        mockRequest, 'Patient', 'missing', mockDb,
      );

      expect(response.statusCode, equals(404));
    });

    test('returns 400 for invalid request body', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, '123'))
          .thenAnswer((_) async => patient);

      when(() => mockRequest.readAsString())
          .thenAnswer((_) async => 'not json at all');

      final response = await metaDeleteHandler(
        mockRequest, 'Patient', '123', mockDb,
      );

      expect(response.statusCode, equals(400));
    });
  });
}
