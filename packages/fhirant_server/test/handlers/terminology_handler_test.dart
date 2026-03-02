import 'dart:convert';

import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:fhirant_server/src/handlers/terminology_handler.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

void main() {
  setUpAll(() {
    registerFallbackValue(fhir.R4ResourceType.CodeSystem);
  });

  group('validateCodeHandler', () {
    late MockFhirAntDb mockDb;

    setUp(() {
      mockDb = MockFhirAntDb();
    });

    Request _makeGetRequest(String path) {
      return Request('GET', Uri.parse('http://localhost:8080/$path'));
    }

    Request _makePostRequest(String path, Map<String, dynamic> body) {
      return Request(
        'POST',
        Uri.parse('http://localhost:8080/$path'),
        body: jsonEncode(body),
      );
    }

    test('returns 400 when code is missing', () async {
      final request = _makeGetRequest(
          'CodeSystem/\$validate-code?system=http://example.com');

      final response = await validateCodeHandler(request, mockDb);
      expect(response.statusCode, 400);
    });

    test('validates code in instance-level CodeSystem', () async {
      final cs = fhir.CodeSystem.fromJson({
        'resourceType': 'CodeSystem',
        'id': 'cs-1',
        'url': 'http://example.com/cs',
        'status': 'active',
        'content': 'complete',
        'concept': [
          {'code': 'A', 'display': 'Alpha'},
          {
            'code': 'B',
            'display': 'Beta',
            'concept': [
              {'code': 'B1', 'display': 'Beta-One'},
            ],
          },
        ],
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.CodeSystem, 'cs-1'))
          .thenAnswer((_) async => cs);

      final request = _makeGetRequest(
          'CodeSystem/cs-1/\$validate-code?code=A');

      final response = await validateCodeHandler(
          request, mockDb, 'CodeSystem', 'cs-1');
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString()) as Map;
      final params = body['parameter'] as List;
      final result = params.firstWhere((p) => p['name'] == 'result');
      expect(result['valueBoolean'], true);

      final display = params.firstWhere((p) => p['name'] == 'display');
      expect(display['valueString'], 'Alpha');
    });

    test('validates nested code in CodeSystem hierarchy', () async {
      final cs = fhir.CodeSystem.fromJson({
        'resourceType': 'CodeSystem',
        'id': 'cs-1',
        'url': 'http://example.com/cs',
        'status': 'active',
        'content': 'complete',
        'concept': [
          {
            'code': 'parent',
            'display': 'Parent',
            'concept': [
              {'code': 'child', 'display': 'Child Code'},
            ],
          },
        ],
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.CodeSystem, 'cs-1'))
          .thenAnswer((_) async => cs);

      final request = _makeGetRequest(
          'CodeSystem/cs-1/\$validate-code?code=child');

      final response = await validateCodeHandler(
          request, mockDb, 'CodeSystem', 'cs-1');
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString()) as Map;
      final params = body['parameter'] as List;
      final result = params.firstWhere((p) => p['name'] == 'result');
      expect(result['valueBoolean'], true);
    });

    test('returns false for code not in CodeSystem', () async {
      final cs = fhir.CodeSystem.fromJson({
        'resourceType': 'CodeSystem',
        'id': 'cs-1',
        'url': 'http://example.com/cs',
        'status': 'active',
        'content': 'complete',
        'concept': [
          {'code': 'A', 'display': 'Alpha'},
        ],
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.CodeSystem, 'cs-1'))
          .thenAnswer((_) async => cs);

      final request = _makeGetRequest(
          'CodeSystem/cs-1/\$validate-code?code=Z');

      final response = await validateCodeHandler(
          request, mockDb, 'CodeSystem', 'cs-1');
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString()) as Map;
      final params = body['parameter'] as List;
      final result = params.firstWhere((p) => p['name'] == 'result');
      expect(result['valueBoolean'], false);
    });

    test('type-level validate-code looks up CodeSystem by URL', () async {
      final cs = fhir.CodeSystem.fromJson({
        'resourceType': 'CodeSystem',
        'id': 'cs-1',
        'url': 'http://example.com/cs',
        'status': 'active',
        'content': 'complete',
        'concept': [
          {'code': 'X', 'display': 'X-ray'},
        ],
      });

      when(() => mockDb.search(
            resourceType: fhir.R4ResourceType.CodeSystem,
            searchParameters: {'url': ['http://example.com/cs']},
            count: 1,
            hasParameters: any(named: 'hasParameters'),
            offset: any(named: 'offset'),
            sort: any(named: 'sort'),
          )).thenAnswer((_) async => [cs]);

      final request = _makeGetRequest(
          'CodeSystem/\$validate-code?system=http://example.com/cs&code=X');

      final response = await validateCodeHandler(
          request, mockDb, 'CodeSystem');
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString()) as Map;
      final params = body['parameter'] as List;
      final result = params.firstWhere((p) => p['name'] == 'result');
      expect(result['valueBoolean'], true);
    });

    test('validates code against ValueSet with compose.include', () async {
      final vs = fhir.ValueSet.fromJson({
        'resourceType': 'ValueSet',
        'id': 'vs-1',
        'url': 'http://example.com/vs',
        'status': 'active',
        'compose': {
          'include': [
            {
              'system': 'http://example.com/cs',
              'concept': [
                {'code': 'A', 'display': 'Alpha'},
                {'code': 'B', 'display': 'Beta'},
              ],
            },
          ],
        },
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.ValueSet, 'vs-1'))
          .thenAnswer((_) async => vs);

      final request = _makeGetRequest(
          'ValueSet/vs-1/\$validate-code?code=A&system=http://example.com/cs');

      final response = await validateCodeHandler(
          request, mockDb, 'ValueSet', 'vs-1');
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString()) as Map;
      final params = body['parameter'] as List;
      final result = params.firstWhere((p) => p['name'] == 'result');
      expect(result['valueBoolean'], true);
    });

    test('validates code against ValueSet expansion', () async {
      final vs = fhir.ValueSet.fromJson({
        'resourceType': 'ValueSet',
        'id': 'vs-1',
        'url': 'http://example.com/vs',
        'status': 'active',
        'expansion': {
          'timestamp': '2024-01-01T00:00:00Z',
          'contains': [
            {
              'system': 'http://loinc.org',
              'code': '1234-5',
              'display': 'Blood glucose',
            },
          ],
        },
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.ValueSet, 'vs-1'))
          .thenAnswer((_) async => vs);

      final request = _makeGetRequest(
          'ValueSet/vs-1/\$validate-code?code=1234-5&system=http://loinc.org');

      final response = await validateCodeHandler(
          request, mockDb, 'ValueSet', 'vs-1');
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString()) as Map;
      final params = body['parameter'] as List;
      final result = params.firstWhere((p) => p['name'] == 'result');
      expect(result['valueBoolean'], true);
    });

    test('POST with Parameters resource body', () async {
      final cs = fhir.CodeSystem.fromJson({
        'resourceType': 'CodeSystem',
        'id': 'cs-1',
        'url': 'http://example.com/cs',
        'status': 'active',
        'content': 'complete',
        'concept': [
          {'code': 'X', 'display': 'X-ray'},
        ],
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.CodeSystem, 'cs-1'))
          .thenAnswer((_) async => cs);

      final request = _makePostRequest(
        'CodeSystem/cs-1/\$validate-code',
        {
          'resourceType': 'Parameters',
          'parameter': [
            {'name': 'code', 'valueCode': 'X'},
          ],
        },
      );

      final response = await validateCodeHandler(
          request, mockDb, 'CodeSystem', 'cs-1');
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString()) as Map;
      final params = body['parameter'] as List;
      final result = params.firstWhere((p) => p['name'] == 'result');
      expect(result['valueBoolean'], true);
    });

    test('returns 404 when CodeSystem not found', () async {
      when(() => mockDb.getResource(fhir.R4ResourceType.CodeSystem, 'missing'))
          .thenAnswer((_) async => null);

      final request = _makeGetRequest(
          'CodeSystem/missing/\$validate-code?code=X');

      final response = await validateCodeHandler(
          request, mockDb, 'CodeSystem', 'missing');
      expect(response.statusCode, 404);
    });
  });

  group('lookupHandler', () {
    late MockFhirAntDb mockDb;

    setUp(() {
      mockDb = MockFhirAntDb();
    });

    Request _makeGetRequest(String path) {
      return Request('GET', Uri.parse('http://localhost:8080/$path'));
    }

    test('returns 400 when code is missing', () async {
      final request = _makeGetRequest(
          'CodeSystem/\$lookup?system=http://example.com');

      final response = await lookupHandler(request, mockDb);
      expect(response.statusCode, 400);
    });

    test('looks up code in instance-level CodeSystem', () async {
      final cs = fhir.CodeSystem.fromJson({
        'resourceType': 'CodeSystem',
        'id': 'cs-1',
        'url': 'http://example.com/cs',
        'name': 'TestCS',
        'version': '1.0',
        'status': 'active',
        'content': 'complete',
        'concept': [
          {
            'code': 'A',
            'display': 'Alpha',
            'definition': 'First letter',
          },
        ],
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.CodeSystem, 'cs-1'))
          .thenAnswer((_) async => cs);

      final request = _makeGetRequest(
          'CodeSystem/cs-1/\$lookup?code=A');

      final response = await lookupHandler(request, mockDb, 'cs-1');
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString()) as Map;
      final params = body['parameter'] as List;

      final name = params.firstWhere((p) => p['name'] == 'name');
      expect(name['valueString'], 'TestCS');

      final display = params.firstWhere((p) => p['name'] == 'display');
      expect(display['valueString'], 'Alpha');

      final version = params.firstWhere((p) => p['name'] == 'version');
      expect(version['valueString'], '1.0');

      final definition = params.firstWhere((p) => p['name'] == 'definition');
      expect(definition['valueString'], 'First letter');
    });

    test('type-level lookup by system URL', () async {
      final cs = fhir.CodeSystem.fromJson({
        'resourceType': 'CodeSystem',
        'id': 'cs-1',
        'url': 'http://example.com/cs',
        'name': 'TestCS',
        'status': 'active',
        'content': 'complete',
        'concept': [
          {'code': 'B', 'display': 'Bravo'},
        ],
      });

      when(() => mockDb.search(
            resourceType: fhir.R4ResourceType.CodeSystem,
            searchParameters: {'url': ['http://example.com/cs']},
            count: 1,
            hasParameters: any(named: 'hasParameters'),
            offset: any(named: 'offset'),
            sort: any(named: 'sort'),
          )).thenAnswer((_) async => [cs]);

      final request = _makeGetRequest(
          'CodeSystem/\$lookup?system=http://example.com/cs&code=B');

      final response = await lookupHandler(request, mockDb);
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString()) as Map;
      final params = body['parameter'] as List;
      final display = params.firstWhere((p) => p['name'] == 'display');
      expect(display['valueString'], 'Bravo');
    });

    test('returns 404 for code not in CodeSystem', () async {
      final cs = fhir.CodeSystem.fromJson({
        'resourceType': 'CodeSystem',
        'id': 'cs-1',
        'url': 'http://example.com/cs',
        'status': 'active',
        'content': 'complete',
        'concept': [
          {'code': 'A', 'display': 'Alpha'},
        ],
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.CodeSystem, 'cs-1'))
          .thenAnswer((_) async => cs);

      final request = _makeGetRequest(
          'CodeSystem/cs-1/\$lookup?code=Z');

      final response = await lookupHandler(request, mockDb, 'cs-1');
      expect(response.statusCode, 404);
    });

    test('returns 404 when CodeSystem not found by URL', () async {
      when(() => mockDb.search(
            resourceType: fhir.R4ResourceType.CodeSystem,
            searchParameters: {'url': ['http://missing.com']},
            count: 1,
            hasParameters: any(named: 'hasParameters'),
            offset: any(named: 'offset'),
            sort: any(named: 'sort'),
          )).thenAnswer((_) async => []);

      final request = _makeGetRequest(
          'CodeSystem/\$lookup?system=http://missing.com&code=X');

      final response = await lookupHandler(request, mockDb);
      expect(response.statusCode, 404);
    });
  });
}
