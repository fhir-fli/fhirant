import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/resource_handler.dart';
import 'package:fhirant_server/src/utils/response_shaper.dart';
import 'package:fhirant_server/src/utils/search_parser.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

class MockRequest extends Mock implements Request {}

void main() {
  setUpAll(() {
    registerFallbackValue(fhir.R4ResourceType.Patient);
    registerFallbackValue(<String, List<String>>{});
    registerFallbackValue(<String>[]);
  });

  group('_elements in search (getResourcesHandler)', () {
    late MockFhirAntDb mockDb;
    late MockRequest mockRequest;

    setUp(() {
      mockDb = MockFhirAntDb();
      mockRequest = MockRequest();
      when(() => mockRequest.headers).thenReturn({});
      when(() => mockRequest.context).thenReturn({});
    });

    test('_elements=name returns only name plus mandatory fields', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '1',
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
        'name': [
          {'family': 'Smith'},
        ],
        'gender': 'male',
        'birthDate': '1990-01-15',
        'active': true,
      });

      when(() => mockRequest.url).thenReturn(
        Uri.parse('http://localhost:8080/Patient?_elements=name&_count=10'),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse('http://localhost:8080/Patient?_elements=name&_count=10'),
      );
      when(
        () => mockDb.getResourcesWithPagination(
          resourceType: fhir.R4ResourceType.Patient,
          count: 11,
          offset: 0,
        ),
      ).thenAnswer((_) async => [patient]);
      when(
        () => mockDb.getResourceCount(fhir.R4ResourceType.Patient),
      ).thenAnswer((_) async => 1);

      final response = await getResourcesHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final entry = (json['entry'] as List).first;
      final resource = entry['resource'] as Map<String, dynamic>;

      // Mandatory fields always present
      expect(resource['resourceType'], equals('Patient'));
      expect(resource['id'], equals('1'));
      expect(resource.containsKey('meta'), isTrue);

      // Requested field present
      expect(resource.containsKey('name'), isTrue);

      // Non-requested fields absent
      expect(resource.containsKey('gender'), isFalse);
      expect(resource.containsKey('birthDate'), isFalse);
      expect(resource.containsKey('active'), isFalse);
    });

    test('_elements adds SUBSETTED tag to meta.security', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '1',
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
        'name': [
          {'family': 'Smith'},
        ],
        'gender': 'male',
      });

      when(() => mockRequest.url).thenReturn(
        Uri.parse('http://localhost:8080/Patient?_elements=name&_count=10'),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse('http://localhost:8080/Patient?_elements=name&_count=10'),
      );
      when(
        () => mockDb.getResourcesWithPagination(
          resourceType: fhir.R4ResourceType.Patient,
          count: 11,
          offset: 0,
        ),
      ).thenAnswer((_) async => [patient]);
      when(
        () => mockDb.getResourceCount(fhir.R4ResourceType.Patient),
      ).thenAnswer((_) async => 1);

      final response = await getResourcesHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final entry = (json['entry'] as List).first;
      final resource = entry['resource'] as Map<String, dynamic>;
      final security = (resource['meta'] as Map)['security'] as List;
      expect(
        security.any(
          (t) =>
              t['code'] == 'SUBSETTED' &&
              t['system'] ==
                  'http://terminology.hl7.org/CodeSystem/v3-ObservationValue',
        ),
        isTrue,
      );
    });

    test('_elements with multiple fields returns all requested', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '1',
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
        'name': [
          {'family': 'Smith'},
        ],
        'gender': 'male',
        'birthDate': '1990-01-15',
        'active': true,
        'telecom': [
          {'system': 'phone', 'value': '555-1234'},
        ],
      });

      when(() => mockRequest.url).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?_elements=name,gender,telecom&_count=10',
        ),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?_elements=name,gender,telecom&_count=10',
        ),
      );
      when(
        () => mockDb.getResourcesWithPagination(
          resourceType: fhir.R4ResourceType.Patient,
          count: 11,
          offset: 0,
        ),
      ).thenAnswer((_) async => [patient]);
      when(
        () => mockDb.getResourceCount(fhir.R4ResourceType.Patient),
      ).thenAnswer((_) async => 1);

      final response = await getResourcesHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final entry = (json['entry'] as List).first;
      final resource = entry['resource'] as Map<String, dynamic>;

      expect(resource.containsKey('name'), isTrue);
      expect(resource.containsKey('gender'), isTrue);
      expect(resource.containsKey('telecom'), isTrue);
      expect(resource.containsKey('birthDate'), isFalse);
      expect(resource.containsKey('active'), isFalse);
    });

    test('_elements with nonexistent field returns only mandatory fields',
        () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '1',
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
        'name': [
          {'family': 'Smith'},
        ],
        'gender': 'male',
      });

      when(() => mockRequest.url).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?_elements=nonExistentField&_count=10',
        ),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?_elements=nonExistentField&_count=10',
        ),
      );
      when(
        () => mockDb.getResourcesWithPagination(
          resourceType: fhir.R4ResourceType.Patient,
          count: 11,
          offset: 0,
        ),
      ).thenAnswer((_) async => [patient]);
      when(
        () => mockDb.getResourceCount(fhir.R4ResourceType.Patient),
      ).thenAnswer((_) async => 1);

      final response = await getResourcesHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final entry = (json['entry'] as List).first;
      final resource = entry['resource'] as Map<String, dynamic>;

      // Only mandatory fields
      expect(resource['resourceType'], equals('Patient'));
      expect(resource.containsKey('id'), isTrue);
      expect(resource.containsKey('meta'), isTrue);
      // Everything else stripped
      expect(resource.containsKey('name'), isFalse);
      expect(resource.containsKey('gender'), isFalse);
    });

    test('_summary and _elements together returns 400', () async {
      when(() => mockRequest.url).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?_summary=true&_elements=name&_count=10',
        ),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?_summary=true&_elements=name&_count=10',
        ),
      );

      final response = await getResourcesHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(400));
      final body = await response.readAsString();
      expect(body, contains('mutually exclusive'));
    });

    test('_summary=text and _elements together returns 400', () async {
      when(() => mockRequest.url).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?_summary=text&_elements=name&_count=10',
        ),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?_summary=text&_elements=name&_count=10',
        ),
      );

      final response = await getResourcesHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(400));
      final body = await response.readAsString();
      expect(body, contains('mutually exclusive'));
    });

    test('_summary=data and _elements together returns 400', () async {
      when(() => mockRequest.url).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?_summary=data&_elements=name&_count=10',
        ),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?_summary=data&_elements=name&_count=10',
        ),
      );

      final response = await getResourcesHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(400));
      final body = await response.readAsString();
      expect(body, contains('mutually exclusive'));
    });

    test('_summary=false with _elements is allowed (false is no-op)', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '1',
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
        'name': [
          {'family': 'Smith'},
        ],
        'gender': 'male',
      });

      when(() => mockRequest.url).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?_summary=false&_elements=name&_count=10',
        ),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?_summary=false&_elements=name&_count=10',
        ),
      );
      when(
        () => mockDb.getResourcesWithPagination(
          resourceType: fhir.R4ResourceType.Patient,
          count: 11,
          offset: 0,
        ),
      ).thenAnswer((_) async => [patient]);
      when(
        () => mockDb.getResourceCount(fhir.R4ResourceType.Patient),
      ).thenAnswer((_) async => 1);

      final response = await getResourcesHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      // _summary=false is a no-op, so _elements should apply
      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final entry = (json['entry'] as List).first;
      final resource = entry['resource'] as Map<String, dynamic>;
      expect(resource.containsKey('name'), isTrue);
      expect(resource.containsKey('gender'), isFalse);
    });

    test('_elements applies to search results with search params', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '1',
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
        'name': [
          {'family': 'Smith'},
        ],
        'gender': 'male',
        'birthDate': '1990-01-15',
      });

      when(() => mockRequest.url).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?name=Smith&_elements=gender&_count=10',
        ),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?name=Smith&_elements=gender&_count=10',
        ),
      );
      when(
        () => mockDb.search(
          resourceType: fhir.R4ResourceType.Patient,
          searchParameters: {
            'name': ['Smith'],
          },
          count: 11,
          offset: 0,
        ),
      ).thenAnswer((_) async => [patient]);
      when(
        () => mockDb.searchCount(
          resourceType: fhir.R4ResourceType.Patient,
          searchParameters: {
            'name': ['Smith'],
          },
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
      final entry = (json['entry'] as List).first;
      final resource = entry['resource'] as Map<String, dynamic>;
      expect(resource.containsKey('gender'), isTrue);
      expect(resource.containsKey('name'), isFalse);
      expect(resource.containsKey('birthDate'), isFalse);
    });
  });

  group('_elements in read (getResourceByIdHandler)', () {
    late MockFhirAntDb mockDb;
    late MockRequest mockRequest;

    setUp(() {
      mockDb = MockFhirAntDb();
      mockRequest = MockRequest();
      when(() => mockRequest.context).thenReturn({});
    });

    test('_elements=name returns only name plus mandatory fields', () async {
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
        'birthDate': '1990-01-15',
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
      expect(json['resourceType'], equals('Patient'));
      expect(json['id'], equals('123'));
      expect(json.containsKey('meta'), isTrue);
      expect(json.containsKey('name'), isTrue);
      expect(json.containsKey('gender'), isFalse);
      expect(json.containsKey('birthDate'), isFalse);
    });

    test('_elements adds SUBSETTED tag to meta.security', () async {
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
      final security = (json['meta'] as Map)['security'] as List;
      expect(
        security.any(
          (t) =>
              t['code'] == 'SUBSETTED' &&
              t['system'] ==
                  'http://terminology.hl7.org/CodeSystem/v3-ObservationValue',
        ),
        isTrue,
      );
    });

    test('_elements with multiple fields returns all requested', () async {
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
        'birthDate': '1990-01-15',
        'active': true,
      });

      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => patient);
      when(() => mockRequest.url).thenReturn(
        Uri.parse('Patient/123?_elements=name,gender'),
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
      expect(json.containsKey('gender'), isTrue);
      expect(json.containsKey('birthDate'), isFalse);
      expect(json.containsKey('active'), isFalse);
    });

    test('_summary and _elements together returns 400', () async {
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
      });

      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => patient);
      when(() => mockRequest.url).thenReturn(
        Uri.parse('Patient/123?_summary=true&_elements=name'),
      );
      when(() => mockRequest.headers).thenReturn({});

      final response = await getResourceByIdHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(400));
      final body = await response.readAsString();
      expect(body, contains('mutually exclusive'));
    });

    test('_summary=count and _elements together returns 400', () async {
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
      });

      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => patient);
      when(() => mockRequest.url).thenReturn(
        Uri.parse('Patient/123?_summary=count&_elements=name'),
      );
      when(() => mockRequest.headers).thenReturn({});

      final response = await getResourceByIdHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(400));
      final body = await response.readAsString();
      expect(body, contains('mutually exclusive'));
    });

    test('_summary=false with _elements is allowed', () async {
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
        Uri.parse('Patient/123?_summary=false&_elements=name'),
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
    });

    test('no _elements returns full resource', () async {
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
        'birthDate': '1990-01-15',
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
      expect(json.containsKey('name'), isTrue);
      expect(json.containsKey('gender'), isTrue);
      expect(json.containsKey('birthDate'), isTrue);
      // No SUBSETTED tag
      final meta = json['meta'] as Map;
      expect(meta.containsKey('security'), isFalse);
    });
  });

  group('FhirResponseShaper.shapeSummary', () {
    final observation = <String, dynamic>{
      'resourceType': 'Observation',
      'id': 'o1',
      'meta': <String, dynamic>{'versionId': '1'},
      'text': {'status': 'generated', 'div': '<div/>'},
      'status': 'final',
      'code': {'text': 'test'},
      'valueQuantity': {'value': 1},
      'note': [
        {'text': 'a note'},
      ],
      'referenceRange': [
        {'text': 'normal'},
      ],
    };

    test('text keeps text, identity and the top-level mandatory elements', () {
      // 3.1.1.5.8: "Return only the "text" element, the 'id' element, the
      // 'meta' element, and only top-level mandatory elements".
      // Observation.status
      // and .code are 1..1 and used to be cut.
      final shaped = FhirResponseShaper.shapeSummary(observation, 'text');
      expect(shaped.keys.toSet(), {
        'resourceType',
        'id',
        'meta',
        'text',
        'status',
        'code',
      });
    });

    test('true keeps the elements the definition marks summary', () {
      final shaped = FhirResponseShaper.shapeSummary(observation, 'true');
      expect(shaped.containsKey('status'), isTrue);
      expect(shaped.containsKey('code'), isTrue);
      expect(shaped.containsKey('valueQuantity'), isTrue);
      expect(shaped.containsKey('note'), isFalse);
      expect(shaped.containsKey('referenceRange'), isFalse);
      expect(shaped.containsKey('text'), isFalse);
    });

    test('true on a type the old hand list never had is a real subset', () {
      // Provenance was not in the 24-type list, so `_summary=true` on it
      // used to be answered as `_summary=text`. Its R4B definition marks
      // target and recorded summary; agent is mandatory but NOT summary, and
      // entity and policy are neither.
      final provenance = <String, dynamic>{
        'resourceType': 'Provenance',
        'id': 'p1',
        'meta': <String, dynamic>{'versionId': '1'},
        'text': {'status': 'generated', 'div': '<div/>'},
        'target': [
          {'reference': 'Patient/1'},
        ],
        'recorded': '2024-01-01T00:00:00Z',
        'policy': ['http://example.org/policy'],
        'agent': [
          {'who': {'reference': 'Practitioner/1'}},
        ],
        'entity': [
          {'role': 'source', 'what': {'reference': 'Device/1'}},
        ],
      };
      final shaped = FhirResponseShaper.shapeSummary(provenance, 'true');
      expect(shaped.containsKey('target'), isTrue);
      expect(shaped.containsKey('recorded'), isTrue);
      expect(shaped.containsKey('agent'), isFalse);
      expect(shaped.containsKey('policy'), isFalse);
      expect(shaped.containsKey('entity'), isFalse);
      expect(shaped.containsKey('text'), isFalse);
    });

    test('data removes text and tags SUBSETTED', () {
      final shaped = FhirResponseShaper.shapeSummary(observation, 'data');
      expect(shaped.containsKey('text'), isFalse);
      expect(shaped.containsKey('note'), isTrue);
      final security = (shaped['meta'] as Map)['security'] as List;
      expect(security.first['code'], equals('SUBSETTED'));
    });

    test("does not write the tag into the caller's map", () {
      final before = Map<String, dynamic>.from(observation['meta'] as Map);
      FhirResponseShaper.shapeSummary(observation, 'true');
      expect(observation['meta'], equals(before));
    });
  });

  group('FhirResponseShaper.shapeElements', () {
    test('keeps resourceType, id, meta and requested fields', () {
      final json = <String, dynamic>{
        'resourceType': 'Patient',
        'id': '1',
        'meta': <String, dynamic>{'versionId': '1'},
        'name': [
          {'family': 'Smith'},
        ],
        'gender': 'male',
        'birthDate': '1990-01-15',
      };

      final shaped = FhirResponseShaper.shapeElements(json, ['name']);

      expect(shaped['resourceType'], equals('Patient'));
      expect(shaped['id'], equals('1'));
      expect(shaped.containsKey('meta'), isTrue);
      expect(shaped.containsKey('name'), isTrue);
      expect(shaped.containsKey('gender'), isFalse);
      expect(shaped.containsKey('birthDate'), isFalse);
    });

    test('adds SUBSETTED tag', () {
      final json = <String, dynamic>{
        'resourceType': 'Observation',
        'id': '1',
        'meta': <String, dynamic>{'versionId': '1'},
        'status': 'final',
        'code': {
          'text': 'test',
        },
      };

      final shaped = FhirResponseShaper.shapeElements(json, ['status']);

      final security = (shaped['meta'] as Map)['security'] as List;
      expect(security.length, equals(1));
      expect(security.first['code'], equals('SUBSETTED'));
      // Observation.code is 1..1. R4 3.1.1.5.9: "Servers SHOULD always
      // return mandatory elements whether they are requested or not." It
      // used to be cut, which handed back an Observation that would not
      // validate.
      expect(shaped.containsKey('code'), isTrue);
    });

    test('a primitive keeps its _element companion', () {
      final json = <String, dynamic>{
        'resourceType': 'Patient',
        'id': '1',
        'meta': <String, dynamic>{'versionId': '1'},
        'birthDate': '1990-01-15',
        '_birthDate': {
          'extension': [
            {
              'url': 'http://hl7.org/fhir/StructureDefinition/patient-birthTime',
              'valueDateTime': '1990-01-15T08:30:00Z',
            },
          ],
        },
        'gender': 'male',
        '_gender': {'id': 'g1'},
      };

      final shaped = FhirResponseShaper.shapeElements(json, ['birthDate']);

      // json.html: a primitive's id and extensions travel in `_name`; cutting
      // one without the other loses them or leaves an orphan.
      expect(shaped.containsKey('birthDate'), isTrue);
      expect(shaped.containsKey('_birthDate'), isTrue);
      expect(shaped.containsKey('gender'), isFalse);
      expect(shaped.containsKey('_gender'), isFalse);
    });

    test('does not duplicate SUBSETTED tag if already present', () {
      final json = <String, dynamic>{
        'resourceType': 'Patient',
        'id': '1',
        'meta': {
          'versionId': '1',
          'security': [
            {
              'system':
                  'http://terminology.hl7.org/CodeSystem/v3-ObservationValue',
              'code': 'SUBSETTED',
            },
          ],
        },
        'name': [
          {'family': 'Smith'},
        ],
        'gender': 'male',
      };

      final shaped = FhirResponseShaper.shapeElements(json, ['name']);

      final security = (shaped['meta'] as Map)['security'] as List;
      // Should still be just one SUBSETTED tag
      final subsettedCount =
          security.where((t) => t['code'] == 'SUBSETTED').length;
      expect(subsettedCount, equals(1));
    });

    test('empty elements list returns only mandatory fields', () {
      final json = <String, dynamic>{
        'resourceType': 'Patient',
        'id': '1',
        'meta': <String, dynamic>{'versionId': '1'},
        'name': [
          {'family': 'Smith'},
        ],
        'gender': 'male',
      };

      final shaped = FhirResponseShaper.shapeElements(json, []);

      expect(shaped.containsKey('resourceType'), isTrue);
      expect(shaped.containsKey('id'), isTrue);
      expect(shaped.containsKey('meta'), isTrue);
      expect(shaped.containsKey('name'), isFalse);
      expect(shaped.containsKey('gender'), isFalse);
    });

    test('works with Observation resource', () {
      final json = <String, dynamic>{
        'resourceType': 'Observation',
        'id': '1',
        'meta': <String, dynamic>{'versionId': '1'},
        'status': 'final',
        'code': {
          'coding': [
            {
              'system': 'http://loinc.org',
              'code': '12345-6',
            },
          ],
        },
        'valueQuantity': {
          'value': 120,
          'unit': 'mmHg',
        },
        'subject': {
          'reference': 'Patient/1',
        },
      };

      final shaped = FhirResponseShaper.shapeElements(json, ['status', 'code']);

      expect(shaped.containsKey('status'), isTrue);
      expect(shaped.containsKey('code'), isTrue);
      expect(shaped.containsKey('valueQuantity'), isFalse);
      expect(shaped.containsKey('subject'), isFalse);
    });
  });

  group('SearchParameterParser _elements parsing', () {
    test('parses comma-separated _elements', () {
      final result = SearchParameterParser.parseQueryParameters({
        '_elements': ['name,gender,birthDate'],
      });

      final elements = result['elements'] as List<String>?;
      expect(elements, isNotNull);
      expect(elements, equals(['name', 'gender', 'birthDate']));
    });

    test('trims whitespace in _elements values', () {
      final result = SearchParameterParser.parseQueryParameters({
        '_elements': [' name , gender '],
      });

      final elements = result['elements'] as List<String>?;
      expect(elements, equals(['name', 'gender']));
    });

    test('_elements absent returns null', () {
      final result = SearchParameterParser.parseQueryParameters({
        'name': ['Smith'],
      });

      expect(result['elements'], isNull);
    });

    test('_elements is not treated as a search parameter', () {
      final result = SearchParameterParser.parseQueryParameters({
        '_elements': ['name'],
        'name': ['Smith'],
      });

      final searchParams = result['searchParams'] as Map<String, List<String>>?;
      expect(searchParams, isNotNull);
      expect(searchParams!.containsKey('_elements'), isFalse);
      expect(searchParams.containsKey('name'), isTrue);
    });
  });
}
