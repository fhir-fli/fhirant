import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

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

  group(r'Patient $everything E2E', () {
    /// Seed data: one Patient, two Observations referencing it, one Condition
    /// referencing it, one Encounter referencing the Patient, and one
    /// Observation belonging to a different patient.
    Future<void> seedCompartmentData() async {
      // Patient
      await testDb.saveResource(
        fhir.Patient(
          id: 'pat-1'.toFhirString,
          name: [fhir.HumanName(family: 'Smith'.toFhirString)],
        ),
      );

      // Organization (not in patient compartment directly)
      await testDb.saveResource(
        fhir.Organization(
          id: 'org-1'.toFhirString,
          name: 'Test Hospital'.toFhirString,
        ),
      );

      // Two Observations for pat-1
      await testDb.saveResource(
        fhir.Observation(
          id: 'obs-1'.toFhirString,
          status: fhir.ObservationStatus.final_,
          code: fhir.CodeableConcept(
            coding: [
              fhir.Coding(
                system: 'http://loinc.org'.toFhirUri,
                code: '85354-9'.toFhirCode,
              ),
            ],
          ),
          subject: fhir.Reference(reference: 'Patient/pat-1'.toFhirString),
        ),
      );
      await testDb.saveResource(
        fhir.Observation(
          id: 'obs-2'.toFhirString,
          status: fhir.ObservationStatus.final_,
          code: fhir.CodeableConcept(
            coding: [
              fhir.Coding(
                system: 'http://loinc.org'.toFhirUri,
                code: '8480-6'.toFhirCode,
              ),
            ],
          ),
          subject: fhir.Reference(reference: 'Patient/pat-1'.toFhirString),
        ),
      );

      // One Condition for pat-1
      await testDb.saveResource(
        fhir.Condition(
          id: 'cond-1'.toFhirString,
          subject: fhir.Reference(reference: 'Patient/pat-1'.toFhirString),
          code: fhir.CodeableConcept(
            coding: [fhir.Coding(code: 'J06.9'.toFhirCode)],
          ),
        ),
      );

      // Encounter referencing pat-1
      await testDb.saveResource(
        fhir.Encounter(
          id: 'enc-1'.toFhirString,
          status: fhir.EncounterStatus.finished,
          class_: fhir.Coding(code: 'AMB'.toFhirCode),
          subject: fhir.Reference(reference: 'Patient/pat-1'.toFhirString),
        ),
      );

      // Different patient + their observation
      await testDb.saveResource(
        fhir.Patient(
          id: 'pat-2'.toFhirString,
          name: [fhir.HumanName(family: 'Jones'.toFhirString)],
        ),
      );
      await testDb.saveResource(
        fhir.Observation(
          id: 'obs-other'.toFhirString,
          status: fhir.ObservationStatus.final_,
          code: fhir.CodeableConcept(
            coding: [fhir.Coding(code: '12345-6'.toFhirCode)],
          ),
          subject: fhir.Reference(reference: 'Patient/pat-2'.toFhirString),
        ),
      );
    }

    test(r'$everything returns focal + all linked resources', () async {
      await seedCompartmentData();

      final response = await handler(
        testRequest(
          'GET',
          r'/Patient/pat-1/$everything',
          authToken: authToken,
        ),
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], equals('Bundle'));
      expect(body['type'], equals('searchset'));

      final entries = body['entry'] as List;
      // Patient + 2 Observations + 1 Condition + 1 Encounter = 5
      expect(entries.length, equals(5));

      final types = entries.map((e) => e['resource']['resourceType']).toSet();
      expect(
        types,
        containsAll(['Patient', 'Observation', 'Condition', 'Encounter']),
      );

      // Should NOT include obs-other or pat-2
      final ids = entries.map((e) => e['resource']['id']).toSet();
      expect(ids, isNot(contains('obs-other')));
      expect(ids, isNot(contains('pat-2')));
    });

    test(r'$everything excludes other patients resources', () async {
      await seedCompartmentData();

      final response = await handler(
        testRequest(
          'GET',
          r'/Patient/pat-1/$everything',
          authToken: authToken,
        ),
      );

      final body = jsonDecode(await response.readAsString());
      final ids =
          (body['entry'] as List).map((e) => e['resource']['id']).toSet();
      expect(ids, isNot(contains('obs-other')));
      expect(ids, isNot(contains('pat-2')));
    });

    test(r'$everything with _type filter returns only specified types',
        () async {
      await seedCompartmentData();

      final response = await handler(
        testRequest(
          'GET',
          r'/Patient/pat-1/$everything?_type=Observation',
          authToken: authToken,
        ),
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());

      final entries = body['entry'] as List;
      // Focal patient + 2 Observations = 3
      expect(entries.length, equals(3));
      final types = entries.map((e) => e['resource']['resourceType']).toSet();
      expect(types, equals({'Patient', 'Observation'}));
    });

    test(r'$everything with _count returns paginated results', () async {
      await seedCompartmentData();

      final response = await handler(
        testRequest(
          'GET',
          r'/Patient/pat-1/$everything?_count=2',
          authToken: authToken,
        ),
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['total'], equals(5));
      expect((body['entry'] as List).length, equals(2));
    });

    test(r'$everything returns 404 for nonexistent patient', () async {
      await seedCompartmentData();

      final response = await handler(
        testRequest(
          'GET',
          r'/Patient/nonexistent/$everything',
          authToken: authToken,
        ),
      );

      expect(response.statusCode, equals(404));
    });
  });

  group('Compartment search E2E', () {
    Future<void> seedCompartmentData() async {
      await testDb.saveResource(
        fhir.Patient(
          id: 'pat-1'.toFhirString,
          name: [fhir.HumanName(family: 'Smith'.toFhirString)],
        ),
      );
      await testDb.saveResource(
        fhir.Observation(
          id: 'obs-1'.toFhirString,
          status: fhir.ObservationStatus.final_,
          code: fhir.CodeableConcept(
            coding: [
              fhir.Coding(
                system: 'http://loinc.org'.toFhirUri,
                code: '85354-9'.toFhirCode,
              ),
            ],
          ),
          subject: fhir.Reference(reference: 'Patient/pat-1'.toFhirString),
        ),
      );
      await testDb.saveResource(
        fhir.Observation(
          id: 'obs-2'.toFhirString,
          status: fhir.ObservationStatus.final_,
          code: fhir.CodeableConcept(
            coding: [
              fhir.Coding(
                system: 'http://loinc.org'.toFhirUri,
                code: '8480-6'.toFhirCode,
              ),
            ],
          ),
          subject: fhir.Reference(reference: 'Patient/pat-1'.toFhirString),
        ),
      );
      await testDb.saveResource(
        fhir.Observation(
          id: 'obs-other'.toFhirString,
          status: fhir.ObservationStatus.final_,
          code: fhir.CodeableConcept(
            coding: [fhir.Coding(code: '99999'.toFhirCode)],
          ),
          subject: fhir.Reference(reference: 'Patient/pat-2'.toFhirString),
        ),
      );
      await testDb.saveResource(
        fhir.Condition(
          id: 'cond-1'.toFhirString,
          subject: fhir.Reference(reference: 'Patient/pat-1'.toFhirString),
          code: fhir.CodeableConcept(
            coding: [fhir.Coding(code: 'J06.9'.toFhirCode)],
          ),
        ),
      );
      await testDb.saveResource(
        fhir.Encounter(
          id: 'enc-1'.toFhirString,
          status: fhir.EncounterStatus.finished,
          class_: fhir.Coding(code: 'AMB'.toFhirCode),
          subject: fhir.Reference(reference: 'Patient/pat-1'.toFhirString),
        ),
      );
    }

    test('compartment search returns Observations for Patient', () async {
      await seedCompartmentData();

      final response = await handler(
        testRequest(
          'GET',
          '/Patient/pat-1/Observation',
          authToken: authToken,
        ),
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], equals('Bundle'));
      expect(body['type'], equals('searchset'));

      final entries = body['entry'] as List;
      expect(entries.length, equals(2));
      final ids = entries.map((e) => e['resource']['id']).toSet();
      expect(ids, containsAll(['obs-1', 'obs-2']));
      expect(ids, isNot(contains('obs-other')));
    });

    test('compartment search with code filter', () async {
      await seedCompartmentData();

      final response = await handler(
        testRequest(
          'GET',
          '/Patient/pat-1/Observation?code=85354-9',
          authToken: authToken,
        ),
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());

      final entries = body['entry'] as List;
      expect(entries.length, equals(1));
      expect(entries[0]['resource']['id'], equals('obs-1'));
    });

    test('empty compartment search returns empty Bundle', () async {
      await seedCompartmentData();

      final response = await handler(
        testRequest(
          'GET',
          '/Patient/pat-1/MedicationRequest',
          authToken: authToken,
        ),
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['entry'], isNull);
    });

    test('compartment search returns 404 for nonexistent patient', () async {
      await seedCompartmentData();

      final response = await handler(
        testRequest(
          'GET',
          '/Patient/nonexistent/Observation',
          authToken: authToken,
        ),
      );

      expect(response.statusCode, equals(404));
    });

    test('Encounter compartment search', () async {
      await seedCompartmentData();

      // Add an Observation linked to the encounter
      await testDb.saveResource(
        fhir.Observation(
          id: 'obs-enc'.toFhirString,
          status: fhir.ObservationStatus.final_,
          code: fhir.CodeableConcept(
            coding: [fhir.Coding(code: '12345'.toFhirCode)],
          ),
          encounter: fhir.Reference(reference: 'Encounter/enc-1'.toFhirString),
        ),
      );

      final response = await handler(
        testRequest(
          'GET',
          '/Encounter/enc-1/Observation',
          authToken: authToken,
        ),
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      final entries = body['entry'] as List;
      expect(entries.length, equals(1));
      expect(entries[0]['resource']['id'], equals('obs-enc'));
    });
  });

  group('a patient-scoped search over a multi-resource compartment', () {
    // Against the real database, not a mock. The handler built `_id` as one
    // element per id, and since fhir_r4_db 0.11.0 the elements of a value
    // list are ANDed, so it asked for a resource whose id was every id at
    // once and returned an empty bundle: a patient-scoped client saw none of
    // its own data. The mocked test in resource_handler_test.dart could not
    // catch it, because it asserted the broken shape and then answered it.
    setUp(() async {
      await testDb.saveResource(fhir.Patient(id: 'pat-1'.toFhirString));
      for (final id in ['obs-1', 'obs-2', 'obs-3']) {
        await testDb.saveResource(
          fhir.Observation(
            id: id.toFhirString,
            status: fhir.ObservationStatus.final_,
            code: fhir.CodeableConcept(text: 'weight'.toFhirString),
            subject: fhir.Reference(reference: 'Patient/pat-1'.toFhirString),
          ),
        );
      }
      // A second patient's observation, which must never appear.
      await testDb.saveResource(fhir.Patient(id: 'pat-2'.toFhirString));
      await testDb.saveResource(
        fhir.Observation(
          id: 'obs-other'.toFhirString,
          status: fhir.ObservationStatus.final_,
          code: fhir.CodeableConcept(text: 'weight'.toFhirString),
          subject: fhir.Reference(reference: 'Patient/pat-2'.toFhirString),
        ),
      );
    });

    test('returns every resource in the compartment, not none', () async {
      final response = await handler(
        testRequest(
          'GET',
          '/Observation',
          authToken: generateTestToken(
            scopes: ['patient/Observation.rs'],
            patientId: 'pat-1',
          ),
        ),
      );

      expect(response.statusCode, 200);
      final bundle =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final ids = ((bundle['entry'] as List?) ?? [])
          .map((e) => (e as Map)['resource'] as Map)
          .map((r) => r['id'] as String)
          .toList()
        ..sort();
      expect(ids, ['obs-1', 'obs-2', 'obs-3']);
    });
  });
}
