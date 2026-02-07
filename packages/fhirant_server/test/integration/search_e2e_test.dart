import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:test/test.dart';
import 'package:shelf/shelf.dart';

import 'test_helpers.dart';

void main() {
  late FhirAntDb testDb;
  late Handler handler;
  late String authToken;

  setUp(() async {
    final server = await createTestServer();
    testDb = server.db;
    handler = server.handler;
    authToken = generateTestToken();
  });

  tearDown(() async {
    await testDb.close();
  });

  group('Search E2E Integration Tests', () {
    test('Search by name returns matching Patients', () async {
      await testDb.saveResource(fhir.Patient(
        id: 'search-name-1'.toFhirString,
        name: [
          fhir.HumanName(
            family: 'Johnson'.toFhirString,
            given: ['Alice'.toFhirString],
          ),
        ],
      ));
      await testDb.saveResource(fhir.Patient(
        id: 'search-name-2'.toFhirString,
        name: [
          fhir.HumanName(
            family: 'Williams'.toFhirString,
            given: ['Bob'.toFhirString],
          ),
        ],
      ));
      await testDb.saveResource(fhir.Patient(
        id: 'search-name-3'.toFhirString,
        name: [
          fhir.HumanName(
            family: 'Johnson'.toFhirString,
            given: ['Charlie'.toFhirString],
          ),
        ],
      ));

      final response = await handler(testRequest(
        'GET',
        '/Patient?family=Johnson',
        authToken: authToken,
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], equals('Bundle'));
      expect(body['type'], equals('searchset'));
      expect(body['total'], equals(2));
      expect(body['entry'], hasLength(2));
    });

    test('Search by identifier (token) returns matching Patient', () async {
      await testDb.saveResource(fhir.Patient(
        id: 'search-token-1'.toFhirString,
        identifier: [
          fhir.Identifier(
            system: 'http://hospital.example/mrn'.toFhirUri,
            value: 'MRN-12345'.toFhirString,
          ),
        ],
        name: [fhir.HumanName(family: 'TokenPatient'.toFhirString)],
      ));
      await testDb.saveResource(fhir.Patient(
        id: 'search-token-2'.toFhirString,
        identifier: [
          fhir.Identifier(
            system: 'http://hospital.example/mrn'.toFhirUri,
            value: 'MRN-67890'.toFhirString,
          ),
        ],
        name: [fhir.HumanName(family: 'OtherPatient'.toFhirString)],
      ));

      final response = await handler(testRequest(
        'GET',
        '/Patient?identifier=http://hospital.example/mrn|MRN-12345',
        authToken: authToken,
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['total'], equals(1));
      expect(body['entry'], hasLength(1));
      expect(body['entry'][0]['resource']['id'], equals('search-token-1'));
    });

    test('Search with _count=1 returns paginated Bundle with next link',
        () async {
      for (var i = 1; i <= 3; i++) {
        await testDb.saveResource(fhir.Patient(
          id: 'page-$i'.toFhirString,
          name: [fhir.HumanName(family: 'PageTest'.toFhirString)],
        ));
      }

      final response = await handler(testRequest(
        'GET',
        '/Patient?family=PageTest&_count=1',
        authToken: authToken,
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['entry'], hasLength(1));
      expect(body['total'], equals(3));

      // Should have a next link
      final links = body['link'] as List?;
      expect(links, isNotNull);
      final nextLink = links?.firstWhere(
        (l) => l['relation'] == 'next',
        orElse: () => null,
      );
      expect(nextLink, isNotNull);
    });

    test('Search with _sort=family returns ordered results', () async {
      await testDb.saveResource(fhir.Patient(
        id: 'sort-z'.toFhirString,
        name: [fhir.HumanName(family: 'Zebra'.toFhirString)],
      ));
      await testDb.saveResource(fhir.Patient(
        id: 'sort-a'.toFhirString,
        name: [fhir.HumanName(family: 'Apple'.toFhirString)],
      ));
      await testDb.saveResource(fhir.Patient(
        id: 'sort-m'.toFhirString,
        name: [fhir.HumanName(family: 'Mango'.toFhirString)],
      ));

      final response = await handler(testRequest(
        'GET',
        '/Patient?_sort=family',
        authToken: authToken,
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      final entries = body['entry'] as List;
      expect(entries.length, greaterThanOrEqualTo(3));

      final families = entries
          .map((e) => e['resource']['name'][0]['family'] as String)
          .toList();
      expect(families, equals(List.from(families)..sort()));
    });

    test('Search with no matches returns empty Bundle', () async {
      final response = await handler(testRequest(
        'GET',
        '/Patient?family=NonExistentFamilyName',
        authToken: authToken,
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], equals('Bundle'));
      expect(body['type'], equals('searchset'));
      expect(body['total'], equals(0));
      // Empty entry list may serialize as null or []
      final entries = body['entry'] as List?;
      expect(entries == null || entries.isEmpty, isTrue);
    });

    test('Search by birthdate returns matching Patient', () async {
      await testDb.saveResource(fhir.Patient(
        id: 'search-dob-1'.toFhirString,
        name: [fhir.HumanName(family: 'DobTest'.toFhirString)],
        birthDate: fhir.FhirDate.fromString('1985-06-15'),
      ));
      await testDb.saveResource(fhir.Patient(
        id: 'search-dob-2'.toFhirString,
        name: [fhir.HumanName(family: 'DobTest2'.toFhirString)],
        birthDate: fhir.FhirDate.fromString('2000-03-20'),
      ));

      final response = await handler(testRequest(
        'GET',
        '/Patient?birthdate=1985-06-15',
        authToken: authToken,
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['total'], equals(1));
      expect(body['entry'][0]['resource']['id'], equals('search-dob-1'));
    });

    test('Search Observation by code returns matching resource', () async {
      await testDb.saveResource(fhir.Observation(
        id: 'obs-bp'.toFhirString,
        status: fhir.ObservationStatus.final_,
        code: fhir.CodeableConcept(
          coding: [
            fhir.Coding(
              system: 'http://loinc.org'.toFhirUri,
              code: '85354-9'.toFhirCode,
              display: 'Blood pressure panel'.toFhirString,
            ),
          ],
        ),
      ));
      await testDb.saveResource(fhir.Observation(
        id: 'obs-hr'.toFhirString,
        status: fhir.ObservationStatus.final_,
        code: fhir.CodeableConcept(
          coding: [
            fhir.Coding(
              system: 'http://loinc.org'.toFhirUri,
              code: '8867-4'.toFhirCode,
              display: 'Heart rate'.toFhirString,
            ),
          ],
        ),
      ));

      final response = await handler(testRequest(
        'GET',
        '/Observation?code=http://loinc.org|85354-9',
        authToken: authToken,
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['total'], equals(1));
      expect(body['entry'][0]['resource']['id'], equals('obs-bp'));
    });

    test('Search by _id returns specific resource', () async {
      await testDb.saveResource(fhir.Patient(
        id: 'id-search-1'.toFhirString,
        name: [fhir.HumanName(family: 'IdSearch'.toFhirString)],
      ));
      await testDb.saveResource(fhir.Patient(
        id: 'id-search-2'.toFhirString,
        name: [fhir.HumanName(family: 'IdSearch'.toFhirString)],
      ));

      final response = await handler(testRequest(
        'GET',
        '/Patient?_id=id-search-1',
        authToken: authToken,
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['total'], equals(1));
      expect(body['entry'][0]['resource']['id'], equals('id-search-1'));
    });

    test('Search with _include returns referenced resources', () async {
      // Create an Organization first
      await testDb.saveResource(fhir.Organization(
        id: 'include-org-1'.toFhirString,
        name: 'Test Hospital'.toFhirString,
      ));

      // Create a Patient that references the Organization
      await testDb.saveResource(fhir.Patient(
        id: 'include-pat-1'.toFhirString,
        name: [fhir.HumanName(family: 'IncludeTest'.toFhirString)],
        managingOrganization: fhir.Reference(
          reference: 'Organization/include-org-1'.toFhirString,
        ),
      ));

      final response = await handler(testRequest(
        'GET',
        '/Patient?family=IncludeTest&_include=Patient:managingOrganization',
        authToken: authToken,
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      // total reflects only matched resources (the Patient), not includes
      expect(body['total'], equals(1));
      // entry should contain both the Patient and the included Organization
      expect(body['entry'], hasLength(2));

      final types = (body['entry'] as List)
          .map((e) => e['resource']['resourceType'] as String)
          .toList();
      expect(types, contains('Patient'));
      expect(types, contains('Organization'));
    });

    test('Search with no matches returns empty Bundle with entry array',
        () async {
      final response = await handler(testRequest(
        'GET',
        '/Condition?code=nonexistent-code',
        authToken: authToken,
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], equals('Bundle'));
      expect(body['type'], equals('searchset'));
      expect(body['total'], equals(0));
      // Bug 5 fix: entry should now be an empty array, not null
      expect(body['entry'], isA<List>());
      expect(body['entry'], isEmpty);
    });
  });
}
