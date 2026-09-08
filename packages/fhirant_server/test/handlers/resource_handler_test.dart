import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/resource_handler.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

// Mock classes
class MockFhirAntDb extends Mock implements FhirAntDb {}

class MockRequest extends Mock implements Request {}

void main() {
  setUpAll(() {
    // Register fallback values for mocktail
    registerFallbackValue(<String, List<String>>{});
    registerFallbackValue(<String>[]);
    registerFallbackValue(fhir.R4ResourceType.Patient);
    registerFallbackValue(const CompartmentScope('Patient', 'x'));
  });

  group('deleteResourceHandler', () {
    late MockFhirAntDb mockDb;
    late MockRequest mockRequest;

    setUp(() {
      mockDb = MockFhirAntDb();
      mockRequest = MockRequest();
      when(() => mockRequest.context).thenReturn({});
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
      when(() => mockRequest.headers).thenReturn({});
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
      when(() => mockRequest.headers).thenReturn({});
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

    test('If-Match matching allows delete', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {
          'versionId': '3',
          'lastUpdated': DateTime.now().toIso8601String(),
        },
      });

      when(
        () => mockRequest.url,
      ).thenReturn(Uri.parse('http://localhost:8080/Patient/123'));
      when(() => mockRequest.headers).thenReturn({
        'if-match': 'W/"3"',
      });
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => patient);
      when(
        () => mockDb.deleteResource(
          fhir.R4ResourceType.Patient,
          '123',
          ifMatchVersion: any(named: 'ifMatchVersion'),
        ),
      ).thenAnswer((_) async => true);

      final response = await deleteResourceHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(204));
    });

    test('If-Match non-matching returns 412', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {
          'versionId': '5',
          'lastUpdated': DateTime.now().toIso8601String(),
        },
      });

      when(
        () => mockRequest.url,
      ).thenReturn(Uri.parse('http://localhost:8080/Patient/123'));
      when(() => mockRequest.headers).thenReturn({
        'if-match': 'W/"1"',
      });
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => patient);
      // The store checks If-Match inside its delete and refuses.
      when(
        () => mockDb.deleteResource(
          fhir.R4ResourceType.Patient,
          '123',
          ifMatchVersion: '1',
        ),
      ).thenThrow(const VersionConflict(expected: '1', actual: '5'));

      final response = await deleteResourceHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(412));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('OperationOutcome'));
    });

    test('no If-Match header allows delete normally', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'meta': {
          'versionId': '3',
          'lastUpdated': DateTime.now().toIso8601String(),
        },
      });

      when(
        () => mockRequest.url,
      ).thenReturn(Uri.parse('http://localhost:8080/Patient/123'));
      when(() => mockRequest.headers).thenReturn({});
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
    });

    test('patient scope denies delete of resource outside compartment',
        () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'pat-2',
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
      });

      when(() => mockRequest.url)
          .thenReturn(Uri.parse('http://localhost:8080/Patient/pat-2'));
      when(() => mockRequest.headers).thenReturn({});
      when(() => mockRequest.context).thenReturn({
        'auth_user': {
          'scopes': ['patient/Patient.r', 'patient/Patient.d'],
          'patientId': 'pat-1',
        },
      });
      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, 'pat-2'))
          .thenAnswer((_) async => patient);
      // A Patient can be in another Patient's compartment through `link`
      // (compartmentdefinition-patient), so the store is asked; here it
      // says no.
      when(
        () => mockDb.searchCount(
          resourceType: fhir.R4ResourceType.Patient,
          searchParameters: {
            '_id': ['pat-2'],
          },
          hasParameters: any(named: 'hasParameters'),
          compartment: any(named: 'compartment'),
        ),
      ).thenAnswer((_) async => 0);

      final response = await deleteResourceHandler(
        mockRequest,
        'Patient',
        'pat-2',
        mockDb,
      );

      expect(response.statusCode, equals(403));
    });

    test('patient scope allows delete of own Patient resource', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'pat-1',
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
      });

      when(() => mockRequest.url)
          .thenReturn(Uri.parse('http://localhost:8080/Patient/pat-1'));
      when(() => mockRequest.headers).thenReturn({});
      when(() => mockRequest.context).thenReturn({
        'auth_user': {
          'scopes': ['patient/Patient.d'],
          'patientId': 'pat-1',
        },
      });
      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, 'pat-1'))
          .thenAnswer((_) async => patient);
      when(() => mockDb.deleteResource(fhir.R4ResourceType.Patient, 'pat-1'))
          .thenAnswer((_) async => true);

      final response = await deleteResourceHandler(
        mockRequest,
        'Patient',
        'pat-1',
        mockDb,
      );

      expect(response.statusCode, equals(204));
    });
  });

  group('getResourcesHandler', () {
    late MockFhirAntDb mockDb;
    late MockRequest mockRequest;

    setUp(() {
      mockDb = MockFhirAntDb();
      mockRequest = MockRequest();
      when(() => mockRequest.headers).thenReturn({});
      when(() => mockRequest.context).thenReturn({});
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
          count: 11,
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
          count: 11,
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
          count: 11,
          offset: 0,
        ),
      ).thenAnswer((_) async => patients);
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
      expect(json['resourceType'], equals('Bundle'));
      expect((json['entry'] as List).length, equals(1));

      verify(
        () => mockDb.search(
          resourceType: fhir.R4ResourceType.Patient,
          searchParameters: {
            'name': ['Smith'],
          },
          count: 11,
          offset: 0,
        ),
      ).called(1);
      verifyNever(
        () => mockDb.getResourcesWithPagination(
          resourceType: fhir.R4ResourceType.Patient,
          count: 11,
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
          count: 21,
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
          count: 21,
          offset: 0,
        ),
      ).called(1);
    });

    test('pagination links include next when more results exist', () async {
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
        // The third row is the probe: the handler asks for count + 1 and a
        // `next` link is emitted because this row came back, not because a
        // total said so. Before, the stub claimed a total of 3 and returned
        // 2, which only worked because nothing checked.
        fhir.Patient.fromJson({
          'resourceType': 'Patient',
          'id': '3',
          'meta': {'lastUpdated': DateTime.now().toIso8601String()},
        }),
      ];

      when(() => mockRequest.url).thenReturn(
        Uri.parse('http://localhost:8080/Patient?_count=2&_offset=0'),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse('http://localhost:8080/Patient?_count=2&_offset=0'),
      );
      when(
        () => mockDb.getResourcesWithPagination(
          resourceType: fhir.R4ResourceType.Patient,
          count: 3,
          offset: 0,
        ),
      ).thenAnswer((_) async => patients);
      when(
        () => mockDb.getResourceCount(fhir.R4ResourceType.Patient),
      ).thenAnswer((_) async => 3);

      final response = await getResourcesHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['total'], equals(3));
      expect(
        (json['entry'] as List).length,
        2,
        reason: 'the probe row is dropped',
      );

      final links = json['link'] as List?;
      expect(links, isNotNull);
      // A 'next' link because a row past the page exists
      final linkRelations = links!.map((l) => l['relation'] as String).toList();
      expect(linkRelations, contains('next'));
      expect(linkRelations, contains('first'));
    });

    test(
        '_include adds referenced resources to bundle with correct '
        'search.mode and fullUrl', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'pt-inc-1',
        'managingOrganization': {'reference': 'Organization/org-inc-1'},
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
      });
      final org = fhir.Organization.fromJson({
        'resourceType': 'Organization',
        'id': 'org-inc-1',
        'name': 'Test Hospital',
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
      });

      when(() => mockRequest.url).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?_include=Patient:managingOrganization&_count=10',
        ),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?_include=Patient:managingOrganization&_count=10',
        ),
      );
      when(() => mockDb.getResources(any(), any())).thenAnswer((i) async {
        final type = i.positionalArguments[0] as fhir.R4ResourceType;
        final out = <fhir.Resource>[];
        for (final id in i.positionalArguments[1] as Iterable<String>) {
          final r = await mockDb.getResource(type, id);
          if (r != null) out.add(r);
        }
        return out;
      });
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
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Organization, 'org-inc-1'),
      ).thenAnswer((_) async => org);
      // The include follows the search parameter through the reference
      // index (3.1.1.5.4), not the JSON.
      when(
        () => mockDb.referenceTargets(
          'Patient',
          any(),
          parameter: 'managingOrganization',
        ),
      ).thenAnswer((_) async => {('Organization', 'org-inc-1')});

      final response = await getResourcesHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final entries = json['entry'] as List;
      expect(entries.length, equals(2));

      // Check search.mode on entries
      final patientEntry = entries.firstWhere(
        (e) => (e['resource'] as Map)['resourceType'] == 'Patient',
      );
      final orgEntry = entries.firstWhere(
        (e) => (e['resource'] as Map)['resourceType'] == 'Organization',
      );
      expect(patientEntry['search']['mode'], equals('match'));
      expect(orgEntry['search']['mode'], equals('include'));

      // Check fullUrl uses each resource's own type (Bug 2 fix)
      expect(patientEntry['fullUrl'], contains('Patient/pt-inc-1'));
      expect(orgEntry['fullUrl'], contains('Organization/org-inc-1'));
    });

    test('_revinclude adds referencing resources to bundle with search.mode',
        () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'pt-rev-1',
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
      });
      final obs = fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': 'obs-rev-1',
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '12345-6'},
          ],
        },
        'subject': {'reference': 'Patient/pt-rev-1'},
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
      });

      when(() => mockRequest.url).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?_revinclude=Observation:subject&_count=10',
        ),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?_revinclude=Observation:subject&_count=10',
        ),
      );
      when(() => mockDb.getResources(any(), any())).thenAnswer((i) async {
        final type = i.positionalArguments[0] as fhir.R4ResourceType;
        final out = <fhir.Resource>[];
        for (final id in i.positionalArguments[1] as Iterable<String>) {
          final r = await mockDb.getResource(type, id);
          if (r != null) out.add(r);
        }
        return out;
      });
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
      when(
        () => mockDb.search(
          resourceType: fhir.R4ResourceType.Observation,
          count: any(named: 'count'),
          searchParameters: {
            'subject': ['Patient/pt-rev-1'],
          },
        ),
      ).thenAnswer((_) async => [obs]);

      final response = await getResourcesHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final entries = json['entry'] as List;
      expect(entries.length, equals(2));

      final patientEntry = entries.firstWhere(
        (e) => (e['resource'] as Map)['resourceType'] == 'Patient',
      );
      final obsEntry = entries.firstWhere(
        (e) => (e['resource'] as Map)['resourceType'] == 'Observation',
      );
      expect(patientEntry['search']['mode'], equals('match'));
      expect(obsEntry['search']['mode'], equals('include'));
      // fullUrl uses Observation type, not Patient
      expect(obsEntry['fullUrl'], contains('Observation/obs-rev-1'));
    });

    test('_include with wildcard (*) extracts all references', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'pt-wild-1',
        'managingOrganization': {'reference': 'Organization/org-wild-1'},
        'generalPractitioner': [
          {'reference': 'Practitioner/prac-wild-1'},
        ],
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
      });
      final org = fhir.Organization.fromJson({
        'resourceType': 'Organization',
        'id': 'org-wild-1',
        'name': 'Test Hospital',
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
      });
      final prac = fhir.Practitioner.fromJson({
        'resourceType': 'Practitioner',
        'id': 'prac-wild-1',
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
      });

      when(() => mockRequest.url).thenReturn(
        Uri.parse('http://localhost:8080/Patient?_include=Patient:*&_count=10'),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse('http://localhost:8080/Patient?_include=Patient:*&_count=10'),
      );
      when(() => mockDb.getResources(any(), any())).thenAnswer((i) async {
        final type = i.positionalArguments[0] as fhir.R4ResourceType;
        final out = <fhir.Resource>[];
        for (final id in i.positionalArguments[1] as Iterable<String>) {
          final r = await mockDb.getResource(type, id);
          if (r != null) out.add(r);
        }
        return out;
      });
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
      when(
        () =>
            mockDb.getResource(fhir.R4ResourceType.Organization, 'org-wild-1'),
      ).thenAnswer((_) async => org);
      when(
        () =>
            mockDb.getResource(fhir.R4ResourceType.Practitioner, 'prac-wild-1'),
      ).thenAnswer((_) async => prac);
      when(
        () => mockDb.referenceTargets('Patient', any()),
      ).thenAnswer(
        (_) async => {
          ('Organization', 'org-wild-1'),
          ('Practitioner', 'prac-wild-1'),
        },
      );

      final response = await getResourcesHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final entries = json['entry'] as List;
      // Patient + Organization + Practitioner
      expect(entries.length, equals(3));
      final types = entries
          .map((e) => (e['resource'] as Map)['resourceType'] as String)
          .toSet();
      expect(types, containsAll(['Patient', 'Organization', 'Practitioner']));
    });

    test('_include:iterate resolves transitive references', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'pt-iter-1',
        'managingOrganization': {'reference': 'Organization/org-iter-1'},
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
      });
      final org = fhir.Organization.fromJson({
        'resourceType': 'Organization',
        'id': 'org-iter-1',
        'partOf': {'reference': 'Organization/org-iter-parent'},
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
      });
      final parentOrg = fhir.Organization.fromJson({
        'resourceType': 'Organization',
        'id': 'org-iter-parent',
        'name': 'Parent Hospital',
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
      });

      when(() => mockRequest.url).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?_include=Patient:managingOrganization&_include:iterate=Organization:partOf&_count=10',
        ),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?_include=Patient:managingOrganization&_include:iterate=Organization:partOf&_count=10',
        ),
      );
      when(() => mockDb.getResources(any(), any())).thenAnswer((i) async {
        final type = i.positionalArguments[0] as fhir.R4ResourceType;
        final out = <fhir.Resource>[];
        for (final id in i.positionalArguments[1] as Iterable<String>) {
          final r = await mockDb.getResource(type, id);
          if (r != null) out.add(r);
        }
        return out;
      });
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
      when(
        () =>
            mockDb.getResource(fhir.R4ResourceType.Organization, 'org-iter-1'),
      ).thenAnswer((_) async => org);
      // Patient:managingOrganization on the match, then Organization:partOf
      // on what was included, then nothing more.
      when(
        () => mockDb.referenceTargets(
          'Patient',
          any(),
          parameter: 'managingOrganization',
        ),
      ).thenAnswer((_) async => {('Organization', 'org-iter-1')});
      when(
        () => mockDb.referenceTargets(
          'Organization',
          any(),
          parameter: 'partOf',
        ),
      ).thenAnswer((invocation) async {
        final ids = invocation.positionalArguments[1] as Iterable<String>;
        return ids.contains('org-iter-1')
            ? {('Organization', 'org-iter-parent')}
            : <(String, String)>{};
      });
      when(
        () => mockDb.getResource(
          fhir.R4ResourceType.Organization,
          'org-iter-parent',
        ),
      ).thenAnswer((_) async => parentOrg);

      final response = await getResourcesHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final entries = json['entry'] as List;
      // Patient + org-iter-1 (from _include) +
      // org-iter-parent (from _include:iterate)
      expect(entries.length, equals(3));
      final ids =
          entries.map((e) => (e['resource'] as Map)['id'] as String).toSet();
      expect(ids, containsAll(['pt-iter-1', 'org-iter-1', 'org-iter-parent']));
    });

    test('_revinclude:iterate resolves transitive reverse references',
        () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'pt-reviter-1',
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
      });
      final encounter = fhir.Encounter.fromJson({
        'resourceType': 'Encounter',
        'id': 'enc-reviter-1',
        'status': 'finished',
        'class': {'code': 'AMB'},
        'subject': {'reference': 'Patient/pt-reviter-1'},
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
      });
      final obs = fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': 'obs-reviter-1',
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '12345-6'},
          ],
        },
        'encounter': {'reference': 'Encounter/enc-reviter-1'},
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
      });

      when(() => mockRequest.url).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?_revinclude=Encounter:subject&_revinclude:iterate=Observation:encounter&_count=10',
        ),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?_revinclude=Encounter:subject&_revinclude:iterate=Observation:encounter&_count=10',
        ),
      );
      when(() => mockDb.getResources(any(), any())).thenAnswer((i) async {
        final type = i.positionalArguments[0] as fhir.R4ResourceType;
        final out = <fhir.Resource>[];
        for (final id in i.positionalArguments[1] as Iterable<String>) {
          final r = await mockDb.getResource(type, id);
          if (r != null) out.add(r);
        }
        return out;
      });
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
      when(
        () => mockDb.search(
          resourceType: fhir.R4ResourceType.Encounter,
          count: any(named: 'count'),
          searchParameters: {
            'subject': ['Patient/pt-reviter-1'],
          },
        ),
      ).thenAnswer((_) async => [encounter]);
      when(
        () => mockDb.search(
          resourceType: fhir.R4ResourceType.Observation,
          count: any(named: 'count'),
          searchParameters: {
            'encounter': ['Encounter/enc-reviter-1'],
          },
        ),
      ).thenAnswer((_) async => [obs]);
      // Second iteration tries Observation with encounter=Observation/obs-reviter-1 — no match
      when(
        () => mockDb.search(
          resourceType: fhir.R4ResourceType.Observation,
          count: any(named: 'count'),
          searchParameters: {
            'encounter': ['Observation/obs-reviter-1'],
          },
        ),
      ).thenAnswer((_) async => []);

      final response = await getResourcesHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final entries = json['entry'] as List;
      // Patient + Encounter (revinclude) + Observation (revinclude:iterate)
      expect(entries.length, equals(3));
      final types = entries
          .map((e) => (e['resource'] as Map)['resourceType'] as String)
          .toSet();
      expect(types, containsAll(['Patient', 'Encounter', 'Observation']));
    });

    test('_include + _summary=text returns 400', () async {
      when(() => mockRequest.url).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?_include=Patient:managingOrganization&_summary=text',
        ),
      );

      final response = await getResourcesHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(400));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('OperationOutcome'));
    });

    test('malformed _revinclude without search param is ignored', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'pt-malrev-1',
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
      });

      when(() => mockRequest.url).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?_revinclude=Observation&_count=10',
        ),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?_revinclude=Observation&_count=10',
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
      final entries = json['entry'] as List;
      // Only the Patient — malformed _revinclude is skipped
      expect(entries.length, equals(1));
      // No search calls made for revinclude
      verifyNever(
        () => mockDb.search(
          resourceType: fhir.R4ResourceType.Observation,
          searchParameters: any(named: 'searchParameters'),
        ),
      );
    });

    test('sort parameter forwarded to search', () async {
      final patients = [
        fhir.Patient.fromJson({
          'resourceType': 'Patient',
          'id': '1',
          'meta': {'lastUpdated': DateTime.now().toIso8601String()},
        }),
      ];

      when(() => mockRequest.url).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?name=Smith&_sort=-name&_count=10',
        ),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?name=Smith&_sort=-name&_count=10',
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
          sort: ['-name'],
        ),
      ).thenAnswer((_) async => patients);
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
      verify(
        () => mockDb.search(
          resourceType: fhir.R4ResourceType.Patient,
          searchParameters: {
            'name': ['Smith'],
          },
          count: 11,
          offset: 0,
          sort: ['-name'],
        ),
      ).called(1);
    });

    test('_summary=count returns bundle with total only, no entries', () async {
      when(() => mockRequest.url).thenReturn(
        Uri.parse('http://localhost:8080/Patient?_summary=count'),
      );
      // The count bundle carries a self link (R4 3.1.1.6), built from the
      // requested URI.
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse('http://localhost:8080/Patient?_summary=count'),
      );
      when(
        () => mockDb.getResourceCount(fhir.R4ResourceType.Patient),
      ).thenAnswer((_) async => 5);

      final response = await getResourcesHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('Bundle'));
      expect(json['total'], equals(5));
      // No entry array in count-only bundle
      expect(json.containsKey('entry'), isFalse);
    });

    test('_summary=text returns only narrative fields', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '1',
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
        'text': {
          'status': 'generated',
          'div': '<div xmlns="http://www.w3.org/1999/xhtml">Test</div>',
        },
        'name': [
          {'family': 'Smith'},
        ],
        'gender': 'male',
      });

      when(() => mockRequest.url).thenReturn(
        Uri.parse('http://localhost:8080/Patient?_summary=text&_count=10'),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse('http://localhost:8080/Patient?_summary=text&_count=10'),
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
      expect(resource.containsKey('id'), isTrue);
      expect(resource.containsKey('text'), isTrue);
      expect(resource.containsKey('name'), isFalse);
      expect(resource.containsKey('gender'), isFalse);
      // Has SUBSETTED tag
      final security = (resource['meta'] as Map)['security'] as List;
      expect(security.any((t) => t['code'] == 'SUBSETTED'), isTrue);
    });

    test('_summary=data excludes text field', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '1',
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
        'text': {
          'status': 'generated',
          'div': '<div xmlns="http://www.w3.org/1999/xhtml">Test</div>',
        },
        'name': [
          {'family': 'Smith'},
        ],
      });

      when(() => mockRequest.url).thenReturn(
        Uri.parse('http://localhost:8080/Patient?_summary=data&_count=10'),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse('http://localhost:8080/Patient?_summary=data&_count=10'),
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
      expect(resource.containsKey('text'), isFalse);
      expect(resource.containsKey('name'), isTrue);
    });

    test('_elements returns subset plus SUBSETTED tag', () async {
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
          'http://localhost:8080/Patient?_elements=name,gender&_count=10',
        ),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse(
          'http://localhost:8080/Patient?_elements=name,gender&_count=10',
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
      expect(resource.containsKey('birthDate'), isFalse);
      final security = (resource['meta'] as Map)['security'] as List;
      expect(security.any((t) => t['code'] == 'SUBSETTED'), isTrue);
    });

    test('_summary=false returns full resource', () async {
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
        Uri.parse('http://localhost:8080/Patient?_summary=false&_count=10'),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse('http://localhost:8080/Patient?_summary=false&_count=10'),
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
    });

    test('empty search results return bundle with total 0', () async {
      when(() => mockRequest.url).thenReturn(
        Uri.parse('http://localhost:8080/Patient?name=NonExistent&_count=10'),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse('http://localhost:8080/Patient?name=NonExistent&_count=10'),
      );
      when(
        () => mockDb.search(
          resourceType: fhir.R4ResourceType.Patient,
          searchParameters: {
            'name': ['NonExistent'],
          },
          count: 11,
          offset: 0,
        ),
      ).thenAnswer((_) async => []);
      when(
        () => mockDb.searchCount(
          resourceType: fhir.R4ResourceType.Patient,
          searchParameters: {
            'name': ['NonExistent'],
          },
        ),
      ).thenAnswer((_) async => 0);

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
      expect(json['total'], equals(0));
      // Entry may be null or empty list depending on serialization
      final entries = json['entry'] as List?;
      expect(entries == null || entries.isEmpty, isTrue);
    });

    test('search bundle includes self link', () async {
      final patients = [
        fhir.Patient.fromJson({
          'resourceType': 'Patient',
          'id': '1',
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
          count: 11,
          offset: 0,
        ),
      ).thenAnswer((_) async => patients);
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
      final links = json['link'] as List?;
      expect(links, isNotNull);
      final selfLink = links!.firstWhere(
        (l) => l['relation'] == 'self',
        orElse: () => null,
      );
      expect(selfLink, isNotNull);
      expect(
        selfLink['url'] as String,
        contains('Patient?name=Smith'),
      );
    });

    test('empty search bundle includes self link', () async {
      when(() => mockRequest.url).thenReturn(
        Uri.parse('http://localhost:8080/Patient?name=Nobody&_count=10'),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse('http://localhost:8080/Patient?name=Nobody&_count=10'),
      );
      when(
        () => mockDb.search(
          resourceType: fhir.R4ResourceType.Patient,
          searchParameters: {
            'name': ['Nobody'],
          },
          count: 11,
          offset: 0,
        ),
      ).thenAnswer((_) async => []);
      when(
        () => mockDb.searchCount(
          resourceType: fhir.R4ResourceType.Patient,
          searchParameters: {
            'name': ['Nobody'],
          },
        ),
      ).thenAnswer((_) async => 0);

      final response = await getResourcesHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final links = json['link'] as List?;
      expect(links, isNotNull);
      final selfLink = links!.firstWhere(
        (l) => l['relation'] == 'self',
        orElse: () => null,
      );
      expect(selfLink, isNotNull);
      expect(
        selfLink['url'] as String,
        contains('Patient?name=Nobody'),
      );
    });

    test('patient scope restricts Patient search to own ID', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'pat-1',
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
      });

      when(() => mockRequest.url).thenReturn(
        Uri.parse('http://localhost:8080/Patient'),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse('http://localhost:8080/Patient'),
      );
      when(() => mockRequest.context).thenReturn({
        'auth_user': {
          'scopes': ['patient/Patient.r', 'patient/Observation.r'],
          'patientId': 'pat-1',
        },
      });
      // The scope is the compartment context of the search itself (R4B
      // 3.1.1.2), not an `_id` the handler injects: the store answers
      // Patient/pat-1's compartment, which for the focal type is pat-1 and
      // any Patient linked to it.
      when(
        () => mockDb.search(
          resourceType: fhir.R4ResourceType.Patient,
          searchParameters: any(named: 'searchParameters'),
          hasParameters: any(named: 'hasParameters'),
          count: any(named: 'count'),
          offset: any(named: 'offset'),
          sort: any(named: 'sort'),
          compartment: any(named: 'compartment'),
        ),
      ).thenAnswer((_) async => [patient]);
      when(
        () => mockDb.searchCount(
          resourceType: fhir.R4ResourceType.Patient,
          searchParameters: any(named: 'searchParameters'),
          hasParameters: any(named: 'hasParameters'),
          compartment: any(named: 'compartment'),
        ),
      ).thenAnswer((_) async => 1);

      final response = await getResourcesHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString()) as Map;
      final entries = body['entry'] as List;
      expect(entries.length, 1);
      expect((entries[0]['resource'] as Map)['id'], 'pat-1');
      final scope = verify(
        () => mockDb.search(
          resourceType: fhir.R4ResourceType.Patient,
          searchParameters: any(named: 'searchParameters'),
          hasParameters: any(named: 'hasParameters'),
          count: any(named: 'count'),
          offset: any(named: 'offset'),
          sort: any(named: 'sort'),
          compartment: captureAny(named: 'compartment'),
        ),
      ).captured.single as CompartmentScope;
      expect(scope.type, 'Patient');
      expect(scope.id, 'pat-1');
    });

    test('patient scope returns empty for non-compartment resource type',
        () async {
      when(() => mockRequest.url).thenReturn(
        Uri.parse('http://localhost:8080/StructureDefinition'),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse('http://localhost:8080/StructureDefinition'),
      );
      when(() => mockRequest.context).thenReturn({
        'auth_user': {
          'scopes': ['patient/Patient.r'],
          'patientId': 'pat-1',
        },
      });
      // The store decides membership: a type the Patient compartment does
      // not include is an empty result and a count of 0
      // (search_compartment_test.dart in fhir_r4_db pins that).
      when(
        () => mockDb.search(
          resourceType: fhir.R4ResourceType.StructureDefinition,
          searchParameters: any(named: 'searchParameters'),
          hasParameters: any(named: 'hasParameters'),
          count: any(named: 'count'),
          offset: any(named: 'offset'),
          sort: any(named: 'sort'),
          compartment: any(named: 'compartment'),
        ),
      ).thenAnswer((_) async => []);
      when(
        () => mockDb.searchCount(
          resourceType: fhir.R4ResourceType.StructureDefinition,
          searchParameters: any(named: 'searchParameters'),
          hasParameters: any(named: 'hasParameters'),
          compartment: any(named: 'compartment'),
        ),
      ).thenAnswer((_) async => 0);

      final response = await getResourcesHandler(
        mockRequest,
        'StructureDefinition',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['total'], 0);
      expect(body['entry'], isNull);
    });

    test('patient scope restricts Observation search to compartment', () async {
      final obs = fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': 'obs-1',
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '1234-5'},
          ],
        },
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
      });

      when(() => mockRequest.url).thenReturn(
        Uri.parse('http://localhost:8080/Observation'),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse('http://localhost:8080/Observation'),
      );
      when(() => mockRequest.context).thenReturn({
        'auth_user': {
          'scopes': ['patient/Observation.r'],
          'patientId': 'pat-1',
        },
      });
      when(
        () => mockDb.search(
          resourceType: fhir.R4ResourceType.Observation,
          searchParameters: any(named: 'searchParameters'),
          hasParameters: any(named: 'hasParameters'),
          count: any(named: 'count'),
          offset: any(named: 'offset'),
          sort: any(named: 'sort'),
          compartment: any(named: 'compartment'),
        ),
      ).thenAnswer((_) async => [obs]);
      when(
        () => mockDb.searchCount(
          resourceType: fhir.R4ResourceType.Observation,
          searchParameters: any(named: 'searchParameters'),
          hasParameters: any(named: 'hasParameters'),
          compartment: any(named: 'compartment'),
        ),
      ).thenAnswer((_) async => 1);

      final response = await getResourcesHandler(
        mockRequest,
        'Observation',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['total'], 1);
      // The search ran inside Patient/pat-1's compartment; no `_id` list.
      final captured = verify(
        () => mockDb.search(
          resourceType: fhir.R4ResourceType.Observation,
          searchParameters: captureAny(named: 'searchParameters'),
          hasParameters: any(named: 'hasParameters'),
          count: any(named: 'count'),
          offset: any(named: 'offset'),
          sort: any(named: 'sort'),
          compartment: captureAny(named: 'compartment'),
        ),
      ).captured;
      expect(captured[0], isNull, reason: 'no _id injected');
      final scope = captured[1] as CompartmentScope;
      expect(scope.type, 'Patient');
      expect(scope.id, 'pat-1');
    });

    test('no patient scope does not restrict search', () async {
      when(() => mockRequest.url).thenReturn(
        Uri.parse('http://localhost:8080/Patient'),
      );
      when(() => mockRequest.requestedUri).thenReturn(
        Uri.parse('http://localhost:8080/Patient'),
      );
      // system-level scopes — no patient restriction
      when(() => mockRequest.context).thenReturn({
        'auth_user': {
          'scopes': ['system/Patient.r'],
        },
      });
      when(
        () => mockDb.getResourcesWithPagination(
          resourceType: fhir.R4ResourceType.Patient,
          count: 21,
          offset: 0,
        ),
      ).thenAnswer((_) async => []);
      when(() => mockDb.getResourceCount(fhir.R4ResourceType.Patient))
          .thenAnswer((_) async => 0);

      final response = await getResourcesHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      // No compartment: the unscoped pagination path ran, not a search.
      verifyNever(
        () => mockDb.search(
          resourceType: any(named: 'resourceType'),
          searchParameters: any(named: 'searchParameters'),
          hasParameters: any(named: 'hasParameters'),
          count: any(named: 'count'),
          offset: any(named: 'offset'),
          sort: any(named: 'sort'),
          compartment: any(named: 'compartment'),
        ),
      );
    });
  });

  group('conditionalDeleteHandler', () {
    late MockFhirAntDb mockDb;
    late MockRequest mockRequest;

    setUp(() {
      mockDb = MockFhirAntDb();
      mockRequest = MockRequest();
      when(() => mockDb.transaction<int>(any())).thenAnswer(
        (i) => (i.positionalArguments.first as Future<int> Function())(),
      );
    });

    test('returns 400 when no search params provided', () async {
      when(() => mockRequest.url).thenReturn(
        Uri.parse('http://localhost:8080/Patient'),
      );

      final response = await conditionalDeleteHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(400));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('OperationOutcome'));
    });

    test('returns 204 when single match found', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'cond-del-1',
        'name': [
          {'family': 'CondDelete'},
        ],
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
      });

      when(() => mockRequest.url).thenReturn(
        Uri.parse('http://localhost:8080/Patient?name=CondDelete'),
      );
      when(
        () => mockDb.search(
          resourceType: fhir.R4ResourceType.Patient,
          count: kMaxConditionalDeletes + 1,
          searchParameters: {
            'name': ['CondDelete'],
          },
        ),
      ).thenAnswer((_) async => [patient]);
      when(
        () => mockDb.deleteResource(fhir.R4ResourceType.Patient, 'cond-del-1'),
      ).thenAnswer((_) async => true);

      final response = await conditionalDeleteHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(204));
      verify(
        () => mockDb.deleteResource(fhir.R4ResourceType.Patient, 'cond-del-1'),
      ).called(1);
    });

    test('returns 204 when multiple matches found (deletes all)', () async {
      final patient1 = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'multi-1',
        'name': [
          {'family': 'MultiMatch'},
        ],
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
      });
      final patient2 = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'multi-2',
        'name': [
          {'family': 'MultiMatch'},
        ],
        'meta': {'lastUpdated': DateTime.now().toIso8601String()},
      });

      when(() => mockRequest.url).thenReturn(
        Uri.parse('http://localhost:8080/Patient?name=MultiMatch'),
      );
      when(
        () => mockDb.search(
          resourceType: fhir.R4ResourceType.Patient,
          count: kMaxConditionalDeletes + 1,
          searchParameters: {
            'name': ['MultiMatch'],
          },
        ),
      ).thenAnswer((_) async => [patient1, patient2]);
      when(
        () => mockDb.deleteResource(fhir.R4ResourceType.Patient, 'multi-1'),
      ).thenAnswer((_) async => true);
      when(
        () => mockDb.deleteResource(fhir.R4ResourceType.Patient, 'multi-2'),
      ).thenAnswer((_) async => true);

      final response = await conditionalDeleteHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(204));
      verify(
        () => mockDb.deleteResource(fhir.R4ResourceType.Patient, 'multi-1'),
      ).called(1);
      verify(
        () => mockDb.deleteResource(fhir.R4ResourceType.Patient, 'multi-2'),
      ).called(1);
    });

    test('returns 200 when no matches found', () async {
      when(() => mockRequest.url).thenReturn(
        Uri.parse('http://localhost:8080/Patient?name=NoMatch'),
      );
      when(
        () => mockDb.search(
          resourceType: fhir.R4ResourceType.Patient,
          count: kMaxConditionalDeletes + 1,
          searchParameters: {
            'name': ['NoMatch'],
          },
        ),
      ).thenAnswer((_) async => []);

      final response = await conditionalDeleteHandler(
        mockRequest,
        'Patient',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('OperationOutcome'));
      verifyNever(() => mockDb.deleteResource(any(), any()));
    });

    test('returns 400 for invalid resource type', () async {
      when(() => mockRequest.url).thenReturn(
        Uri.parse('http://localhost:8080/InvalidType?name=Test'),
      );

      final response = await conditionalDeleteHandler(
        mockRequest,
        'InvalidType',
        mockDb,
      );

      expect(response.statusCode, equals(400));
    });
  });
}
