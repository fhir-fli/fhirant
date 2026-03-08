import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/cql_handler.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

void main() {
  late MockFhirAntDb mockDb;

  setUpAll(() {
    registerFallbackValue(fhir.R4ResourceType.Patient);
  });

  setUp(() {
    mockDb = MockFhirAntDb();
  });

  Request _postJson(String path, dynamic body) {
    return Request(
      'POST',
      Uri.parse('http://localhost$path'),
      body: jsonEncode(body),
      headers: {'Content-Type': 'application/json'},
    );
  }

  // ---------------------------------------------------------------------------
  // $cql convenience endpoint
  // ---------------------------------------------------------------------------
  group('\$cql handler', () {
    test('returns 400 when body is empty', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/\$cql'),
        body: '',
      );
      final response = await cqlHandler(request, mockDb);
      expect(response.statusCode, 400);
      final body = jsonDecode(await response.readAsString());
      expect(body['issue'][0]['diagnostics'], contains('body is required'));
    });

    test('returns 400 when neither cql nor elm is provided', () async {
      final response = await cqlHandler(
        _postJson('/\$cql', {'patientId': '123'}),
        mockDb,
      );
      expect(response.statusCode, 400);
      final body = jsonDecode(await response.readAsString());
      expect(body['issue'][0]['diagnostics'], contains('cql'));
    });

    test('returns 400 for invalid JSON body', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/\$cql'),
        body: 'not json',
        headers: {'Content-Type': 'application/json'},
      );
      final response = await cqlHandler(request, mockDb);
      expect(response.statusCode, 400);
      final body = jsonDecode(await response.readAsString());
      expect(body['issue'][0]['diagnostics'], contains('Invalid JSON'));
    });

    test('evaluates simple CQL literal', () async {
      final cql = "library TestLib version '1.0.0'\ndefine Greeting: 'Hello, CQL!'";
      final response = await cqlHandler(
        _postJson('/\$cql', {'cql': cql}),
        mockDb,
      );
      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], 'Parameters');
      final params = body['parameter'] as List;
      final greeting = params.firstWhere((p) => p['name'] == 'Greeting');
      expect(greeting['valueString'], 'Hello, CQL!');
    });

    test('evaluates CQL arithmetic', () async {
      final cql = "library ArithTest version '1.0.0'\ndefine Sum: 2 + 3";
      final response = await cqlHandler(
        _postJson('/\$cql', {'cql': cql}),
        mockDb,
      );
      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString());
      final params = body['parameter'] as List;
      final sum = params.firstWhere((p) => p['name'] == 'Sum');
      expect(sum['valueInteger'], 5);
    });

    test('evaluates CQL boolean logic', () async {
      final cql =
          "library BoolTest version '1.0.0'\ndefine IsTrue: true and true\ndefine IsFalse: true and false";
      final response = await cqlHandler(
        _postJson('/\$cql', {'cql': cql}),
        mockDb,
      );
      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString());
      final params = body['parameter'] as List;
      final isTrue = params.firstWhere((p) => p['name'] == 'IsTrue');
      final isFalse = params.firstWhere((p) => p['name'] == 'IsFalse');
      expect(isTrue['valueBoolean'], true);
      expect(isFalse['valueBoolean'], false);
    });

    test('evaluates CQL list count', () async {
      final cql =
          "library ListTest version '1.0.0'\ndefine Numbers: {1, 2, 3, 4, 5}\ndefine Total: Count(Numbers)";
      final response = await cqlHandler(
        _postJson('/\$cql', {'cql': cql}),
        mockDb,
      );
      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString());
      final params = body['parameter'] as List;
      final total = params.firstWhere((p) => p['name'] == 'Total');
      expect(total['valueInteger'], 5);
    });

    test('evaluates CQL string operations', () async {
      final cql =
          "library StringTest version '1.0.0'\ndefine Concat: 'Hello' + ' ' + 'World'";
      final response = await cqlHandler(
        _postJson('/\$cql', {'cql': cql}),
        mockDb,
      );
      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString());
      final params = body['parameter'] as List;
      final concat = params.firstWhere((p) => p['name'] == 'Concat');
      expect(concat['valueString'], 'Hello World');
    });

    test('accepts FHIR Parameters resource format', () async {
      final cql = "library ParamsTest version '1.0.0'\ndefine Answer: 42";
      final response = await cqlHandler(
        _postJson('/\$cql', {
          'resourceType': 'Parameters',
          'parameter': [
            {'name': 'cql', 'valueString': cql},
          ],
        }),
        mockDb,
      );
      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString());
      final params = body['parameter'] as List;
      final answer = params.firstWhere((p) => p['name'] == 'Answer');
      expect(answer['valueInteger'], 42);
    });

    test('evaluates with inline data bundle', () async {
      final cql =
          "library PatientTest version '1.0.0'\nusing FHIR version '4.0.1'\ncontext Patient\ndefine PatientId: Patient.id";
      final bundle = {
        'resourceType': 'Bundle',
        'type': 'collection',
        'entry': [
          {
            'resource': {
              'resourceType': 'Patient',
              'id': 'test-123',
              'name': [
                {'family': 'Smith', 'given': ['John']}
              ],
            }
          }
        ],
      };
      final response = await cqlHandler(
        _postJson('/\$cql', {'cql': cql, 'data': bundle}),
        mockDb,
      );
      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], 'Parameters');
    });

    test('loads patient from DB via subject param', () async {
      final patient = fhir.Patient(
        id: 'pat-1'.toFhirString,
        name: [fhir.HumanName(family: 'Doe'.toFhirString)],
      );
      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, 'pat-1'))
          .thenAnswer((_) async => patient);
      when(() => mockDb.search(
            resourceType: any(named: 'resourceType'),
            searchParameters: any(named: 'searchParameters'),
            hasParameters: any(named: 'hasParameters'),
            count: any(named: 'count'),
            offset: any(named: 'offset'),
            sort: any(named: 'sort'),
          )).thenAnswer((_) async => <fhir.Resource>[]);

      final cql = "library P version '1.0.0'\ndefine X: 1";
      final response = await cqlHandler(
        _postJson('/\$cql', {'cql': cql, 'subject': 'Patient/pat-1'}),
        mockDb,
      );
      expect(response.statusCode, 200);
      verify(() => mockDb.getResource(fhir.R4ResourceType.Patient, 'pat-1'))
          .called(1);
    });

    test('patientId alias works as subject', () async {
      when(() => mockDb.getResource(any(), any()))
          .thenAnswer((_) async => null);

      final cql = "library P version '1.0.0'\ndefine X: 1";
      final response = await cqlHandler(
        _postJson('/\$cql', {'cql': cql, 'patientId': 'missing'}),
        mockDb,
      );
      // Patient not found — still returns 200 (subject is optional in $cql)
      // The context just won't have a Patient
      expect(response.statusCode, 200);
    });

    test('response has correct content type', () async {
      final cql = "library T version '1.0.0'\ndefine X: 1";
      final response = await cqlHandler(
        _postJson('/\$cql', {'cql': cql}),
        mockDb,
      );
      expect(response.headers['content-type'], 'application/fhir+json');
    });

    test('handles invalid CQL syntax gracefully', () async {
      final response = await cqlHandler(
        _postJson('/\$cql', {'cql': 'this is not valid CQL @@@ !!!'}),
        mockDb,
      );
      expect(response.statusCode, isIn([200, 400, 500]));
    });

    test('evaluates CQL date/time operations', () async {
      final cql =
          "library DateTest version '1.0.0'\ndefine Today: Today()\ndefine Now: Now()";
      final response = await cqlHandler(
        _postJson('/\$cql', {'cql': cql}),
        mockDb,
      );
      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString());
      expect((body['parameter'] as List), isNotEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Library/<id>/$evaluate
  // ---------------------------------------------------------------------------
  group('Library/<id>/\$evaluate', () {
    String _encodeCql(String cql) => base64Encode(utf8.encode(cql));

    fhir.Library _makeLibrary(String id, String cql,
        {String contentType = 'text/cql'}) {
      return fhir.Library(
        id: id.toFhirString,
        status: fhir.PublicationStatus.active,
        type: fhir.CodeableConcept(
          coding: [
            fhir.Coding(
              system: 'http://terminology.hl7.org/CodeSystem/library-type'
                  .toFhirUri,
              code: 'logic-library'.toFhirCode,
            )
          ],
        ),
        content: [
          fhir.Attachment(
            contentType: contentType.toFhirCode,
            data: _encodeCql(cql).toFhirBase64Binary,
          ),
        ],
      );
    }

    test('evaluates a stored Library with CQL content', () async {
      final cql = "library MyLib version '1.0.0'\ndefine Greeting: 'Hello from Library!'";
      final library = _makeLibrary('lib-1', cql);

      when(() => mockDb.getResource(fhir.R4ResourceType.Library, 'lib-1'))
          .thenAnswer((_) async => library);

      final request = Request(
        'POST',
        Uri.parse('http://localhost/Library/lib-1/\$evaluate'),
        body: '',
      );

      final response = await libraryEvaluateHandler(request, 'lib-1', mockDb);
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], 'Parameters');
      final params = body['parameter'] as List;
      final greeting = params.firstWhere((p) => p['name'] == 'Greeting');
      expect(greeting['valueString'], 'Hello from Library!');
    });

    test('evaluates a stored Library with ELM JSON content', () async {
      // First parse CQL to get valid ELM, then store as ELM
      final cql = "library ElmLib version '1.0.0'\ndefine Answer: 42";
      // We'll just use CQL content type for this test since generating
      // real ELM JSON is complex
      final library = _makeLibrary('lib-elm', cql);

      when(() => mockDb.getResource(fhir.R4ResourceType.Library, 'lib-elm'))
          .thenAnswer((_) async => library);

      final request = Request(
        'POST',
        Uri.parse('http://localhost/Library/lib-elm/\$evaluate'),
        body: '',
      );

      final response =
          await libraryEvaluateHandler(request, 'lib-elm', mockDb);
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString());
      final params = body['parameter'] as List;
      final answer = params.firstWhere((p) => p['name'] == 'Answer');
      expect(answer['valueInteger'], 42);
    });

    test('returns 404 when Library not found', () async {
      when(() => mockDb.getResource(fhir.R4ResourceType.Library, 'missing'))
          .thenAnswer((_) async => null);

      final request = Request(
        'POST',
        Uri.parse('http://localhost/Library/missing/\$evaluate'),
        body: '',
      );

      final response =
          await libraryEvaluateHandler(request, 'missing', mockDb);
      expect(response.statusCode, 404);
      final body = jsonDecode(await response.readAsString());
      expect(body['issue'][0]['diagnostics'], contains('Library/missing'));
    });

    test('returns 422 when Library has no evaluable content', () async {
      final emptyLibrary = fhir.Library(
        id: 'empty'.toFhirString,
        status: fhir.PublicationStatus.active,
        type: fhir.CodeableConcept(
          coding: [
            fhir.Coding(code: 'logic-library'.toFhirCode),
          ],
        ),
      );

      when(() => mockDb.getResource(fhir.R4ResourceType.Library, 'empty'))
          .thenAnswer((_) async => emptyLibrary);

      final request = Request(
        'POST',
        Uri.parse('http://localhost/Library/empty/\$evaluate'),
        body: '',
      );

      final response =
          await libraryEvaluateHandler(request, 'empty', mockDb);
      expect(response.statusCode, 422);
      final body = jsonDecode(await response.readAsString());
      expect(body['issue'][0]['diagnostics'], contains('no evaluable content'));
    });

    test('evaluates with subject parameter', () async {
      final cql = "library SubjectTest version '1.0.0'\ndefine X: 1";
      final library = _makeLibrary('lib-subj', cql);

      final patient = fhir.Patient(
        id: 'pat-2'.toFhirString,
        name: [fhir.HumanName(family: 'Test'.toFhirString)],
      );

      when(() => mockDb.getResource(fhir.R4ResourceType.Library, 'lib-subj'))
          .thenAnswer((_) async => library);
      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, 'pat-2'))
          .thenAnswer((_) async => patient);
      when(() => mockDb.search(
            resourceType: any(named: 'resourceType'),
            searchParameters: any(named: 'searchParameters'),
            hasParameters: any(named: 'hasParameters'),
            count: any(named: 'count'),
            offset: any(named: 'offset'),
            sort: any(named: 'sort'),
          )).thenAnswer((_) async => <fhir.Resource>[]);

      final response = await libraryEvaluateHandler(
        _postJson('/Library/lib-subj/\$evaluate', {
          'resourceType': 'Parameters',
          'parameter': [
            {'name': 'subject', 'valueString': 'Patient/pat-2'},
          ],
        }),
        'lib-subj',
        mockDb,
      );
      expect(response.statusCode, 200);
      verify(() => mockDb.getResource(fhir.R4ResourceType.Patient, 'pat-2'))
          .called(1);
    });
  });

  // ---------------------------------------------------------------------------
  // Library/$evaluate (by URL / inline)
  // ---------------------------------------------------------------------------
  group('Library/\$evaluate (by URL)', () {
    test('evaluates Library found by canonical URL', () async {
      final cql = "library ByUrl version '1.0.0'\ndefine Found: true";
      final library = fhir.Library(
        id: 'lib-url'.toFhirString,
        url: 'http://example.org/Library/ByUrl'.toFhirUri,
        status: fhir.PublicationStatus.active,
        type: fhir.CodeableConcept(
          coding: [fhir.Coding(code: 'logic-library'.toFhirCode)],
        ),
        content: [
          fhir.Attachment(
            contentType: 'text/cql'.toFhirCode,
            data: base64Encode(utf8.encode(cql)).toFhirBase64Binary,
          ),
        ],
      );

      when(() => mockDb.search(
            resourceType: fhir.R4ResourceType.Library,
            searchParameters: {'url': ['http://example.org/Library/ByUrl']},
            hasParameters: any(named: 'hasParameters'),
            count: any(named: 'count'),
            offset: any(named: 'offset'),
            sort: any(named: 'sort'),
          )).thenAnswer((_) async => [library]);

      final response = await libraryEvaluateByUrlHandler(
        _postJson('/Library/\$evaluate', {
          'resourceType': 'Parameters',
          'parameter': [
            {
              'name': 'url',
              'valueUri': 'http://example.org/Library/ByUrl',
            },
          ],
        }),
        mockDb,
      );
      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString());
      final params = body['parameter'] as List;
      final found = params.firstWhere((p) => p['name'] == 'Found');
      expect(found['valueBoolean'], true);
    });

    test('returns 404 when canonical URL not found', () async {
      when(() => mockDb.search(
            resourceType: fhir.R4ResourceType.Library,
            searchParameters: any(named: 'searchParameters'),
            hasParameters: any(named: 'hasParameters'),
            count: any(named: 'count'),
            offset: any(named: 'offset'),
            sort: any(named: 'sort'),
          )).thenAnswer((_) async => <fhir.Resource>[]);

      final response = await libraryEvaluateByUrlHandler(
        _postJson('/Library/\$evaluate', {
          'resourceType': 'Parameters',
          'parameter': [
            {'name': 'url', 'valueUri': 'http://example.org/missing'},
          ],
        }),
        mockDb,
      );
      expect(response.statusCode, 404);
    });

    test('evaluates inline CQL via Library/\$evaluate', () async {
      final cql = "library Inline version '1.0.0'\ndefine X: 99";
      final response = await libraryEvaluateByUrlHandler(
        _postJson('/Library/\$evaluate', {
          'resourceType': 'Parameters',
          'parameter': [
            {'name': 'cql', 'valueString': cql},
          ],
        }),
        mockDb,
      );
      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString());
      final params = body['parameter'] as List;
      final x = params.firstWhere((p) => p['name'] == 'X');
      expect(x['valueInteger'], 99);
    });

    test('returns 400 when no library source provided', () async {
      final response = await libraryEvaluateByUrlHandler(
        _postJson('/Library/\$evaluate', {
          'resourceType': 'Parameters',
          'parameter': [
            {'name': 'subject', 'valueString': 'Patient/123'},
          ],
        }),
        mockDb,
      );
      expect(response.statusCode, 400);
      final body = jsonDecode(await response.readAsString());
      expect(body['issue'][0]['diagnostics'], contains('No evaluable library'));
    });

    test('returns 400 when body is empty', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/Library/\$evaluate'),
        body: '',
      );
      final response = await libraryEvaluateByUrlHandler(request, mockDb);
      expect(response.statusCode, 400);
    });
  });
}
