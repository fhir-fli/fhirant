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
      // FHIR spec: entry must be absent (not empty array) when no results
      expect(body['entry'], isNull);
    });

    test('_include sets search.mode=match on matched and include on included',
        () async {
      await testDb.saveResource(fhir.Organization(
        id: 'mode-org-1'.toFhirString,
        name: 'Mode Hospital'.toFhirString,
      ));
      await testDb.saveResource(fhir.Patient(
        id: 'mode-pat-1'.toFhirString,
        name: [fhir.HumanName(family: 'ModeTest'.toFhirString)],
        managingOrganization: fhir.Reference(
          reference: 'Organization/mode-org-1'.toFhirString,
        ),
      ));

      final response = await handler(testRequest(
        'GET',
        '/Patient?family=ModeTest&_include=Patient:managingOrganization',
        authToken: authToken,
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      final entries = body['entry'] as List;
      expect(entries, hasLength(2));

      final patientEntry = entries.firstWhere(
          (e) => e['resource']['resourceType'] == 'Patient');
      final orgEntry = entries.firstWhere(
          (e) => e['resource']['resourceType'] == 'Organization');
      expect(patientEntry['search']['mode'], equals('match'));
      expect(orgEntry['search']['mode'], equals('include'));
      // fullUrl uses correct resource type
      expect(
          patientEntry['fullUrl'] as String, contains('Patient/mode-pat-1'));
      expect(
          orgEntry['fullUrl'] as String, contains('Organization/mode-org-1'));
    });

    test('_revinclude sets search.mode correctly', () async {
      await testDb.saveResource(fhir.Patient(
        id: 'rev-mode-pat-1'.toFhirString,
        name: [fhir.HumanName(family: 'RevModeTest'.toFhirString)],
      ));
      await testDb.saveResource(fhir.Observation(
        id: 'rev-mode-obs-1'.toFhirString,
        status: fhir.ObservationStatus.final_,
        code: fhir.CodeableConcept(
          coding: [
            fhir.Coding(
              system: 'http://loinc.org'.toFhirUri,
              code: '12345-6'.toFhirCode,
            ),
          ],
        ),
        subject: fhir.Reference(
          reference: 'Patient/rev-mode-pat-1'.toFhirString,
        ),
      ));

      final response = await handler(testRequest(
        'GET',
        '/Patient?family=RevModeTest&_revinclude=Observation:subject',
        authToken: authToken,
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      final entries = body['entry'] as List;
      expect(entries, hasLength(2));

      final patientEntry = entries.firstWhere(
          (e) => e['resource']['resourceType'] == 'Patient');
      final obsEntry = entries.firstWhere(
          (e) => e['resource']['resourceType'] == 'Observation');
      expect(patientEntry['search']['mode'], equals('match'));
      expect(obsEntry['search']['mode'], equals('include'));
    });

    test('_include:iterate resolves multi-level references', () async {
      // Parent org
      await testDb.saveResource(fhir.Organization(
        id: 'iter-parent-org'.toFhirString,
        name: 'Parent Hospital'.toFhirString,
      ));
      // Child org that references parent
      await testDb.saveResource(fhir.Organization(
        id: 'iter-child-org'.toFhirString,
        name: 'Child Clinic'.toFhirString,
        partOf: fhir.Reference(
          reference: 'Organization/iter-parent-org'.toFhirString,
        ),
      ));
      // Patient referencing child org
      await testDb.saveResource(fhir.Patient(
        id: 'iter-pat-1'.toFhirString,
        name: [fhir.HumanName(family: 'IterTest'.toFhirString)],
        managingOrganization: fhir.Reference(
          reference: 'Organization/iter-child-org'.toFhirString,
        ),
      ));

      final response = await handler(testRequest(
        'GET',
        '/Patient?family=IterTest&_include=Patient:managingOrganization&_include:iterate=Organization:partOf',
        authToken: authToken,
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      final entries = body['entry'] as List;
      // Patient + child org (_include) + parent org (_include:iterate)
      expect(entries, hasLength(3));

      final ids =
          entries.map((e) => e['resource']['id'] as String).toSet();
      expect(ids,
          containsAll(['iter-pat-1', 'iter-child-org', 'iter-parent-org']));
    });

    test('search bundle has self link matching request URL', () async {
      await testDb.saveResource(fhir.Patient(
        id: 'self-link-1'.toFhirString,
        name: [fhir.HumanName(family: 'SelfLinkTest'.toFhirString)],
      ));

      final response = await handler(testRequest(
        'GET',
        '/Patient?family=SelfLinkTest',
        authToken: authToken,
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      final links = body['link'] as List?;
      expect(links, isNotNull);
      final selfLink = links!.firstWhere(
        (l) => l['relation'] == 'self',
        orElse: () => null,
      );
      expect(selfLink, isNotNull);
      expect(
        selfLink['url'] as String,
        contains('/Patient?family=SelfLinkTest'),
      );
    });

    test('empty search bundle has self link', () async {
      final response = await handler(testRequest(
        'GET',
        '/Patient?family=NobodyHere',
        authToken: authToken,
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      final links = body['link'] as List?;
      expect(links, isNotNull);
      final selfLink = links!.firstWhere(
        (l) => l['relation'] == 'self',
        orElse: () => null,
      );
      expect(selfLink, isNotNull);
      expect(
        selfLink['url'] as String,
        contains('/Patient?family=NobodyHere'),
      );
    });

    test('_include with wildcard (*) includes all referenced resources',
        () async {
      await testDb.saveResource(fhir.Organization(
        id: 'wild-org-1'.toFhirString,
        name: 'Wild Hospital'.toFhirString,
      ));
      await testDb.saveResource(fhir.Practitioner(
        id: 'wild-prac-1'.toFhirString,
        name: [fhir.HumanName(family: 'WildDoc'.toFhirString)],
      ));
      await testDb.saveResource(fhir.Patient(
        id: 'wild-pat-1'.toFhirString,
        name: [fhir.HumanName(family: 'WildTest'.toFhirString)],
        managingOrganization: fhir.Reference(
          reference: 'Organization/wild-org-1'.toFhirString,
        ),
        generalPractitioner: [
          fhir.Reference(
            reference: 'Practitioner/wild-prac-1'.toFhirString,
          ),
        ],
      ));

      final response = await handler(testRequest(
        'GET',
        '/Patient?family=WildTest&_include=Patient:*',
        authToken: authToken,
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      final entries = body['entry'] as List;
      // Patient + Organization + Practitioner
      expect(entries, hasLength(3));
      final types = entries
          .map((e) => e['resource']['resourceType'] as String)
          .toSet();
      expect(types, containsAll(['Patient', 'Organization', 'Practitioner']));
    });
  });
}
