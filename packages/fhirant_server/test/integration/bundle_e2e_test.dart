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
    authToken = await issueTestToken(testDb);
  });

  tearDown(() async {
    await testDb.close();
  });

  group('Bundle E2E Integration Tests', () {
    test('Transaction with 2 POST entries creates both resources', () async {
      final bundle = fhir.Bundle(
        type: fhir.BundleType.transaction,
        entry: [
          fhir.BundleEntry(
            resource: fhir.Patient(
              id: 'txn-pat-1'.toFhirString,
              name: [fhir.HumanName(family: 'TxnPatient1'.toFhirString)],
            ),
            request: fhir.BundleRequest(
              method: fhir.HTTPVerb.pOST,
              url: fhir.FhirUri('Patient'),
            ),
          ),
          fhir.BundleEntry(
            resource: fhir.Patient(
              id: 'txn-pat-2'.toFhirString,
              name: [fhir.HumanName(family: 'TxnPatient2'.toFhirString)],
            ),
            request: fhir.BundleRequest(
              method: fhir.HTTPVerb.pOST,
              url: fhir.FhirUri('Patient'),
            ),
          ),
        ],
      );

      final response = await handler(
        testRequest(
          'POST',
          '/',
          body: bundle.toJsonString(),
          headers: {'content-type': 'application/fhir+json'},
          authToken: authToken,
        ),
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], equals('Bundle'));
      expect(body['type'], equals('transaction-response'));
      expect(body['entry'], hasLength(2));

      // Verify both resources exist in DB
      // A POST ignores a client id (http.html create; REVIEW-2026-09-08 row
      // 21): the created ids are the response's, not the request's.
      final ids = [
        for (final e in body['entry'] as List)
          (e as Map)['resource']['id'] as String,
      ];
      expect(ids, isNot(contains('txn-pat-1')));
      final pat1 =
          await testDb.getResource(fhir.R4ResourceType.Patient, ids[0]);
      final pat2 =
          await testDb.getResource(fhir.R4ResourceType.Patient, ids[1]);
      expect(pat1, isNotNull);
      expect(pat2, isNotNull);
    });

    test('Bundle with urn:uuid references resolves them', () async {
      final bundle = fhir.Bundle(
        type: fhir.BundleType.transaction,
        entry: [
          fhir.BundleEntry(
            fullUrl: fhir.FhirUri('urn:uuid:org-uuid-1'),
            resource: fhir.Organization(
              id: 'urn-org-1'.toFhirString,
              name: 'Referenced Org'.toFhirString,
            ),
            request: fhir.BundleRequest(
              method: fhir.HTTPVerb.pOST,
              url: fhir.FhirUri('Organization'),
            ),
          ),
          fhir.BundleEntry(
            fullUrl: fhir.FhirUri('urn:uuid:pat-uuid-1'),
            resource: fhir.Patient(
              id: 'urn-pat-1'.toFhirString,
              name: [fhir.HumanName(family: 'UrnPatient'.toFhirString)],
              managingOrganization: fhir.Reference(
                reference: 'urn:uuid:org-uuid-1'.toFhirString,
              ),
            ),
            request: fhir.BundleRequest(
              method: fhir.HTTPVerb.pOST,
              url: fhir.FhirUri('Patient'),
            ),
          ),
        ],
      );

      final response = await handler(
        testRequest(
          'POST',
          '/',
          body: bundle.toJsonString(),
          headers: {'content-type': 'application/fhir+json'},
          authToken: authToken,
        ),
      );

      expect(response.statusCode, equals(200));

      // Verify the Patient's reference was resolved to the Organization the
      // server created (its id, not the client's).
      final body = jsonDecode(await response.readAsString());
      final entries = body['entry'] as List;
      final orgId = (entries[0] as Map)['resource']['id'] as String;
      final patId = (entries[1] as Map)['resource']['id'] as String;
      final patient =
          await testDb.getResource(fhir.R4ResourceType.Patient, patId);
      expect(patient, isNotNull);
      final patJson = patient!.toJson();
      final ref = patJson['managingOrganization']['reference'] as String;
      expect(ref, equals('Organization/$orgId'));
    });

    test('Batch with mixed success/failure returns partial results', () async {
      // Create a patient first so the GET succeeds
      await testDb.saveResource(
        fhir.Patient(
          id: 'batch-existing'.toFhirString,
          name: [fhir.HumanName(family: 'Existing'.toFhirString)],
        ),
      );

      final bundle = fhir.Bundle(
        type: fhir.BundleType.batch,
        entry: [
          // This should succeed: GET existing patient
          fhir.BundleEntry(
            request: fhir.BundleRequest(
              method: fhir.HTTPVerb.gET,
              url: fhir.FhirUri('Patient/batch-existing'),
            ),
          ),
          // This should succeed: POST new patient
          fhir.BundleEntry(
            resource: fhir.Patient(
              id: 'batch-new'.toFhirString,
              name: [fhir.HumanName(family: 'NewBatch'.toFhirString)],
            ),
            request: fhir.BundleRequest(
              method: fhir.HTTPVerb.pOST,
              url: fhir.FhirUri('Patient'),
            ),
          ),
          // This should fail: GET non-existent patient
          fhir.BundleEntry(
            request: fhir.BundleRequest(
              method: fhir.HTTPVerb.gET,
              url: fhir.FhirUri('Patient/does-not-exist'),
            ),
          ),
        ],
      );

      final response = await handler(
        testRequest(
          'POST',
          '/',
          body: bundle.toJsonString(),
          headers: {'content-type': 'application/fhir+json'},
          authToken: authToken,
        ),
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['type'], equals('batch-response'));
      expect(body['entry'], hasLength(3));

      // First entry: successful GET → 200
      final entry0Status = body['entry'][0]['response']['status'] as String;
      expect(entry0Status, contains('200'));

      // Second entry: successful POST → 201
      final entry1Status = body['entry'][1]['response']['status'] as String;
      expect(entry1Status, contains('201'));

      // Third entry: failed GET → 404 (resource not found)
      final entry2Status = body['entry'][2]['response']['status'] as String;
      expect(entry2Status, contains('404'));
    });

    test('Transaction with invalid entry rolls back all changes', () async {
      final bundle = fhir.Bundle(
        type: fhir.BundleType.transaction,
        entry: [
          fhir.BundleEntry(
            resource: fhir.Patient(
              id: 'rollback-pat'.toFhirString,
              name: [fhir.HumanName(family: 'RollbackTest'.toFhirString)],
            ),
            request: fhir.BundleRequest(
              method: fhir.HTTPVerb.pOST,
              url: fhir.FhirUri('Patient'),
            ),
          ),
          // PUT with mismatched resource type/URL to cause a failure
          fhir.BundleEntry(
            resource: fhir.Patient(
              id: 'rollback-wrong'.toFhirString,
              name: [fhir.HumanName(family: 'WrongType'.toFhirString)],
            ),
            request: fhir.BundleRequest(
              method: fhir.HTTPVerb.pUT,
              url: fhir.FhirUri('Observation/rollback-wrong'),
            ),
          ),
        ],
      );

      final response = await handler(
        testRequest(
          'POST',
          '/',
          body: bundle.toJsonString(),
          headers: {'content-type': 'application/fhir+json'},
          authToken: authToken,
        ),
      );

      // Transaction should fail
      final statusCode = response.statusCode;
      expect(statusCode, isNot(equals(200)));

      // The first patient should NOT be in the DB (rolled back)
      final pat =
          await testDb.getResource(fhir.R4ResourceType.Patient, 'rollback-pat');
      expect(pat, isNull);
    });
  });
}
