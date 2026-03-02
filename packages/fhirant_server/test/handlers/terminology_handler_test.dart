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

  group('expandHandler', () {
    late MockFhirAntDb mockDb;

    setUp(() {
      mockDb = MockFhirAntDb();
    });

    Request _makeGetRequest(String path) {
      return Request('GET', Uri.parse('http://localhost:8080/$path'));
    }

    test('returns 400 when no id or url provided', () async {
      final request = _makeGetRequest('ValueSet/\$expand');

      final response = await expandHandler(request, mockDb);
      expect(response.statusCode, 400);
    });

    test('returns 404 when ValueSet not found by id', () async {
      when(() => mockDb.getResource(fhir.R4ResourceType.ValueSet, 'missing'))
          .thenAnswer((_) async => null);

      final request = _makeGetRequest('ValueSet/missing/\$expand');

      final response = await expandHandler(request, mockDb, 'missing');
      expect(response.statusCode, 404);
    });

    test('returns 404 when ValueSet not found by url', () async {
      when(() => mockDb.search(
            resourceType: fhir.R4ResourceType.ValueSet,
            searchParameters: {'url': ['http://missing.com/vs']},
            count: 1,
            hasParameters: any(named: 'hasParameters'),
            offset: any(named: 'offset'),
            sort: any(named: 'sort'),
          )).thenAnswer((_) async => []);

      final request = _makeGetRequest(
          'ValueSet/\$expand?url=http://missing.com/vs');

      final response = await expandHandler(request, mockDb);
      expect(response.statusCode, 404);
    });

    test('returns existing expansion when already expanded', () async {
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
            {
              'system': 'http://loinc.org',
              'code': '5678-9',
              'display': 'Blood pressure',
            },
          ],
        },
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.ValueSet, 'vs-1'))
          .thenAnswer((_) async => vs);

      final request = _makeGetRequest('ValueSet/vs-1/\$expand');

      final response = await expandHandler(request, mockDb, 'vs-1');
      expect(response.statusCode, 200);

      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['resourceType'], 'ValueSet');
      final expansion = body['expansion'] as Map<String, dynamic>;
      final contains = expansion['contains'] as List;
      expect(contains.length, 2);
      expect(contains[0]['code'], '1234-5');
      expect(contains[1]['code'], '5678-9');
    });

    test('expands ValueSet from compose.include with explicit concepts',
        () async {
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

      final request = _makeGetRequest('ValueSet/vs-1/\$expand');

      final response = await expandHandler(request, mockDb, 'vs-1');
      expect(response.statusCode, 200);

      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final expansion = body['expansion'] as Map<String, dynamic>;
      final contains = expansion['contains'] as List;
      expect(contains.length, 2);
      expect(contains[0]['system'], 'http://example.com/cs');
      expect(contains[0]['code'], 'A');
      expect(contains[1]['code'], 'B');
      expect(expansion['total'], 2);
    });

    test('expands ValueSet by resolving CodeSystem from DB', () async {
      final vs = fhir.ValueSet.fromJson({
        'resourceType': 'ValueSet',
        'id': 'vs-1',
        'url': 'http://example.com/vs',
        'status': 'active',
        'compose': {
          'include': [
            {
              'system': 'http://example.com/cs',
            },
          ],
        },
      });

      final cs = fhir.CodeSystem.fromJson({
        'resourceType': 'CodeSystem',
        'id': 'cs-1',
        'url': 'http://example.com/cs',
        'status': 'active',
        'content': 'complete',
        'concept': [
          {'code': 'X', 'display': 'X-ray'},
          {
            'code': 'Y',
            'display': 'Yankee',
            'concept': [
              {'code': 'Y1', 'display': 'Yankee-One'},
            ],
          },
        ],
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.ValueSet, 'vs-1'))
          .thenAnswer((_) async => vs);
      when(() => mockDb.search(
            resourceType: fhir.R4ResourceType.CodeSystem,
            searchParameters: {'url': ['http://example.com/cs']},
            count: 1,
            hasParameters: any(named: 'hasParameters'),
            offset: any(named: 'offset'),
            sort: any(named: 'sort'),
          )).thenAnswer((_) async => [cs]);

      final request = _makeGetRequest('ValueSet/vs-1/\$expand');

      final response = await expandHandler(request, mockDb, 'vs-1');
      expect(response.statusCode, 200);

      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final expansion = body['expansion'] as Map<String, dynamic>;
      final contains = expansion['contains'] as List;
      // Flattened hierarchy: X, Y, Y1
      expect(contains.length, 3);
      expect(contains.map((c) => c['code']).toList(), ['X', 'Y', 'Y1']);
    });

    test('applies filter parameter to expansion', () async {
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
            {
              'system': 'http://loinc.org',
              'code': '5678-9',
              'display': 'Blood pressure',
            },
            {
              'system': 'http://loinc.org',
              'code': '9999-0',
              'display': 'Heart rate',
            },
          ],
        },
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.ValueSet, 'vs-1'))
          .thenAnswer((_) async => vs);

      final request = _makeGetRequest(
          'ValueSet/vs-1/\$expand?filter=blood');

      final response = await expandHandler(request, mockDb, 'vs-1');
      expect(response.statusCode, 200);

      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final expansion = body['expansion'] as Map<String, dynamic>;
      final contains = expansion['contains'] as List;
      expect(contains.length, 2);
      expect(contains[0]['display'], 'Blood glucose');
      expect(contains[1]['display'], 'Blood pressure');
    });

    test('applies offset and count to expansion', () async {
      final vs = fhir.ValueSet.fromJson({
        'resourceType': 'ValueSet',
        'id': 'vs-1',
        'url': 'http://example.com/vs',
        'status': 'active',
        'expansion': {
          'timestamp': '2024-01-01T00:00:00Z',
          'contains': [
            {'system': 'http://ex.com', 'code': 'A', 'display': 'Alpha'},
            {'system': 'http://ex.com', 'code': 'B', 'display': 'Beta'},
            {'system': 'http://ex.com', 'code': 'C', 'display': 'Charlie'},
            {'system': 'http://ex.com', 'code': 'D', 'display': 'Delta'},
          ],
        },
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.ValueSet, 'vs-1'))
          .thenAnswer((_) async => vs);

      final request = _makeGetRequest(
          'ValueSet/vs-1/\$expand?offset=1&count=2');

      final response = await expandHandler(request, mockDb, 'vs-1');
      expect(response.statusCode, 200);

      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final expansion = body['expansion'] as Map<String, dynamic>;
      final contains = expansion['contains'] as List;
      expect(contains.length, 2);
      expect(contains[0]['code'], 'B');
      expect(contains[1]['code'], 'C');
      expect(expansion['total'], 4);
      expect(expansion['offset'], 1);
    });

    test('applies exclude rules during expansion', () async {
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
                {'code': 'C', 'display': 'Charlie'},
              ],
            },
          ],
          'exclude': [
            {
              'system': 'http://example.com/cs',
              'concept': [
                {'code': 'B'},
              ],
            },
          ],
        },
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.ValueSet, 'vs-1'))
          .thenAnswer((_) async => vs);

      final request = _makeGetRequest('ValueSet/vs-1/\$expand');

      final response = await expandHandler(request, mockDb, 'vs-1');
      expect(response.statusCode, 200);

      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final expansion = body['expansion'] as Map<String, dynamic>;
      final contains = expansion['contains'] as List;
      expect(contains.length, 2);
      expect(contains.map((c) => c['code']).toList(), ['A', 'C']);
    });

    test('type-level expand by url parameter', () async {
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
              ],
            },
          ],
        },
      });

      when(() => mockDb.search(
            resourceType: fhir.R4ResourceType.ValueSet,
            searchParameters: {'url': ['http://example.com/vs']},
            count: 1,
            hasParameters: any(named: 'hasParameters'),
            offset: any(named: 'offset'),
            sort: any(named: 'sort'),
          )).thenAnswer((_) async => [vs]);

      final request = _makeGetRequest(
          'ValueSet/\$expand?url=http://example.com/vs');

      final response = await expandHandler(request, mockDb);
      expect(response.statusCode, 200);

      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final expansion = body['expansion'] as Map<String, dynamic>;
      final contains = expansion['contains'] as List;
      expect(contains.length, 1);
      expect(contains[0]['code'], 'A');
    });
  });
}
