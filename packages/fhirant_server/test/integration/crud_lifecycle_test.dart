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

  group('CRUD Lifecycle Integration Tests', () {
    test('POST /Patient creates resource with id and meta', () async {
      final patient = fhir.Patient(
        id: 'test-create-001'.toFhirString,
        name: [
          fhir.HumanName(
            family: 'Smith'.toFhirString,
            given: ['John'.toFhirString],
          ),
        ],
        birthDate: fhir.FhirDate.fromString('1990-01-15'),
      );

      final response = await handler(testRequest(
        'POST',
        '/Patient',
        body: patient.toJsonString(),
        headers: {'content-type': 'application/fhir+json'},
        authToken: authToken,
      ));

      expect(response.statusCode, equals(201));
      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], equals('Patient'));
      expect(body['id'], isNotNull);
      expect(body['meta'], isNotNull);
      expect(body['meta']['versionId'], isNotNull);
      expect(body['meta']['lastUpdated'], isNotNull);
      expect(body['name'][0]['family'], equals('Smith'));
    });

    test('POST /Patient with no ID auto-generates one', () async {
      // Bug 3 fix: POST with no ID should auto-generate an ID and
      // successfully re-fetch to include server-assigned meta
      final patient = fhir.Patient(
        name: [
          fhir.HumanName(
            family: 'AutoId'.toFhirString,
            given: ['Test'.toFhirString],
          ),
        ],
      );

      final response = await handler(testRequest(
        'POST',
        '/Patient',
        body: patient.toJsonString(),
        headers: {'content-type': 'application/fhir+json'},
        authToken: authToken,
      ));

      expect(response.statusCode, equals(201));
      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], equals('Patient'));
      // Should have an auto-generated ID
      expect(body['id'], isNotNull);
      expect((body['id'] as String).isNotEmpty, isTrue);
      // Should have server-assigned meta from re-fetch
      expect(body['meta'], isNotNull);
      expect(body['meta']['versionId'], isNotNull);
      expect(body['meta']['lastUpdated'], isNotNull);
      expect(body['name'][0]['family'], equals('AutoId'));
    });

    test('GET /Patient/{id} reads created resource', () async {
      final patient = fhir.Patient(
        id: 'test-read-123'.toFhirString,
        name: [fhir.HumanName(family: 'ReadTest'.toFhirString)],
      );
      await testDb.saveResource(patient);

      final response = await handler(testRequest(
        'GET',
        '/Patient/test-read-123',
        authToken: authToken,
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], equals('Patient'));
      expect(body['id'], equals('test-read-123'));
      expect(body['name'][0]['family'], equals('ReadTest'));
    });

    test('PUT /Patient/{id} updates resource with new version', () async {
      final patient = fhir.Patient(
        id: 'test-put-456'.toFhirString,
        name: [fhir.HumanName(family: 'Original'.toFhirString)],
      );
      await testDb.saveResource(patient);

      final updated = fhir.Patient(
        id: 'test-put-456'.toFhirString,
        name: [fhir.HumanName(family: 'Updated'.toFhirString)],
      );

      final response = await handler(testRequest(
        'PUT',
        '/Patient/test-put-456',
        body: updated.toJsonString(),
        headers: {'content-type': 'application/fhir+json'},
        authToken: authToken,
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['name'][0]['family'], equals('Updated'));
      expect(body['meta']['versionId'], isNotNull);
    });

    test('PATCH /Patient/{id} applies JSON Patch', () async {
      final patient = fhir.Patient(
        id: 'test-patch-789'.toFhirString,
        name: [fhir.HumanName(family: 'BeforePatch'.toFhirString)],
        active: fhir.FhirBoolean(true),
      );
      await testDb.saveResource(patient);

      final patchDoc = jsonEncode([
        {'op': 'replace', 'path': '/name/0/family', 'value': 'AfterPatch'},
      ]);

      final response = await handler(testRequest(
        'PATCH',
        '/Patient/test-patch-789',
        body: patchDoc,
        headers: {'content-type': 'application/fhir+json'},
        authToken: authToken,
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['name'][0]['family'], equals('AfterPatch'));
    });

    test('DELETE /Patient/{id} removes resource', () async {
      final patient = fhir.Patient(
        id: 'test-delete-abc'.toFhirString,
        name: [fhir.HumanName(family: 'ToDelete'.toFhirString)],
      );
      await testDb.saveResource(patient);

      final response = await handler(testRequest(
        'DELETE',
        '/Patient/test-delete-abc',
        authToken: authToken,
      ));

      expect(response.statusCode, equals(204));
    });

    test('GET deleted Patient returns 404', () async {
      final patient = fhir.Patient(
        id: 'test-gone-def'.toFhirString,
        name: [fhir.HumanName(family: 'WillBeGone'.toFhirString)],
      );
      await testDb.saveResource(patient);
      await testDb.deleteResource(
          fhir.R4ResourceType.Patient, 'test-gone-def');

      final response = await handler(testRequest(
        'GET',
        '/Patient/test-gone-def',
        authToken: authToken,
      ));

      expect(response.statusCode, equals(404));
    });

    test('GET /Patient/{id}/_history/{vid} returns specific version',
        () async {
      final patient = fhir.Patient(
        id: 'test-vread-ghi'.toFhirString,
        name: [fhir.HumanName(family: 'Version1'.toFhirString)],
      );
      await testDb.saveResource(patient);

      final saved = await testDb.getResource(
          fhir.R4ResourceType.Patient, 'test-vread-ghi');
      final v1Id = saved!.meta!.versionId!.toString();

      // Drift stores DateTime as integer seconds by default, so we need
      // >1s delay to get a distinct lastUpdated (history PK includes it)
      await Future.delayed(const Duration(milliseconds: 1100));

      final updated = fhir.Patient(
        id: 'test-vread-ghi'.toFhirString,
        name: [fhir.HumanName(family: 'Version2'.toFhirString)],
      );
      await testDb.saveResource(updated);

      final response = await handler(testRequest(
        'GET',
        '/Patient/test-vread-ghi/_history/$v1Id',
        authToken: authToken,
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['name'][0]['family'], equals('Version1'));
      expect(body['meta']['versionId'], equals(v1Id));
    });

    test('GET /Patient/{id}/_history returns all versions', () async {
      final patient = fhir.Patient(
        id: 'test-history-jkl'.toFhirString,
        name: [fhir.HumanName(family: 'HistV1'.toFhirString)],
      );
      await testDb.saveResource(patient);

      // Drift stores DateTime as integer seconds by default, so we need
      // >1s delay to get a distinct lastUpdated (history PK includes it)
      await Future.delayed(const Duration(milliseconds: 1100));

      final updated = fhir.Patient(
        id: 'test-history-jkl'.toFhirString,
        name: [fhir.HumanName(family: 'HistV2'.toFhirString)],
      );
      await testDb.saveResource(updated);

      final response = await handler(testRequest(
        'GET',
        '/Patient/test-history-jkl/_history',
        authToken: authToken,
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], equals('Bundle'));
      expect(body['type'], equals('history'));
      expect(body['total'], equals(2));
      expect(body['entry'], hasLength(2));
    });
  });
}
