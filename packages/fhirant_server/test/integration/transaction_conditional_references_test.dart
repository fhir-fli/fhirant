import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// R4B http.html 3.1.0.11.2, "Conditional References" (hl7.org/fhir/R4B/
/// http.html, read whole 2026-10-17, verbatim): "in a transaction (and only
/// in a transaction), references to resources may be replaced by a search
/// URI that describes how to find the correct reference", and "When
/// processing transactions, servers SHALL: check all references for search
/// URIs; For search URIs, use the search to locate matching resources; if
/// there are no matches, or multiple matches, the transaction fails, and an
/// error is returned to the user; if there is a single match, the server
/// replaces the search URI with a reference to the matching resource".
///
/// REVIEW-2026-10-17 finding 3: the search URI was stored as written, so an
/// Observation sent with `subject: Patient?identifier=…` (how interface
/// engines send results) never linked to its patient.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String admin;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    admin = await issueTestToken(db, username: 'adm', scopes: ['system/*.*']);
    for (final (id, mrn) in [('p1', 'm1'), ('p2', 'm2'), ('p3', 'dup')]) {
      await db.saveResource(
        fhir.Patient(
          id: id.toFhirString,
          identifier: [
            fhir.Identifier(
              system: 'urn:mrn'.toFhirUri,
              value: mrn.toFhirString,
            ),
          ],
        ),
      );
    }
    await db.saveResource(
      fhir.Patient(
        id: 'p4'.toFhirString,
        identifier: [
          fhir.Identifier(
            system: 'urn:mrn'.toFhirUri,
            value: 'dup'.toFhirString,
          ),
        ],
      ),
    );
  });

  tearDown(() => db.close());

  Map<String, dynamic> observation(String subject) => {
        'resourceType': 'Observation',
        'status': 'final',
        'code': {'text': 'potassium'},
        'subject': {'reference': subject},
      };

  Future<Response> transaction(
    List<Map<String, dynamic>> entries, {
    String? token,
  }) async =>
      handler(
        testRequest(
          'POST',
          '/',
          body: jsonEncode({
            'resourceType': 'Bundle',
            'type': 'transaction',
            'entry': entries,
          }),
          authToken: token ?? admin,
        ),
      );

  Map<String, dynamic> post(Map<String, dynamic> resource) => {
        'resource': resource,
        'request': {'method': 'POST', 'url': resource['resourceType']},
      };

  Future<int> storedObservations() async => (await db.search(
        resourceType: fhir.R4ResourceType.Observation,
        searchParameters: {},
      ))
          .length;

  test('a single match replaces the search URI', () async {
    final response =
        await transaction([post(observation('Patient?identifier=urn:mrn|m1'))]);
    expect(response.statusCode, 200, reason: await response.readAsString());
    final stored = await db.search(
      resourceType: fhir.R4ResourceType.Observation,
      searchParameters: {},
    );
    final obs = stored.single as fhir.Observation;
    expect(obs.subject?.reference?.valueString, 'Patient/p1');
  });

  test('a PUT entry is resolved too', () async {
    final response = await transaction([
      {
        'resource': {...observation('Patient?_id=p2'), 'id': 'o9'},
        'request': {'method': 'PUT', 'url': 'Observation/o9'},
      },
    ]);
    expect(response.statusCode, 200, reason: await response.readAsString());
    final obs = await db.getResource(fhir.R4ResourceType.Observation, 'o9')
        as fhir.Observation?;
    expect(obs?.subject?.reference?.valueString, 'Patient/p2');
  });

  test('no match fails the transaction and stores nothing', () async {
    final response = await transaction([
      post({'resourceType': 'Patient', 'id': 'ignored'}),
      post(observation('Patient?identifier=urn:mrn|nobody')),
    ]);
    expect(response.statusCode, 412);
    expect(await storedObservations(), 0);
    expect(
      (await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {},
      ))
          .length,
      4,
      reason: 'the Patient POST in the same transaction was rolled back',
    );
  });

  test('several matches fail the transaction', () async {
    final response = await transaction(
      [post(observation('Patient?identifier=urn:mrn|dup'))],
    );
    expect(response.statusCode, 412);
    expect(await storedObservations(), 0);
  });

  test("the search runs inside a patient token's compartment", () async {
    final patient = await issueTestToken(
      db,
      username: 'pat',
      scopes: ['patient/*.*'],
      patientId: 'p1',
    );
    final other = await transaction(
      [post(observation('Patient?identifier=urn:mrn|m2'))],
      token: patient,
    );
    expect(
      other.statusCode,
      412,
      reason: "Patient p2 is outside the token's compartment, so the "
          'confined search finds nothing',
    );
    expect(await storedObservations(), 0);
  });

  test('a caller that cannot search the type cannot resolve through it',
      () async {
    final obsOnly = await issueTestToken(
      db,
      username: 'obs',
      scopes: ['user/Observation.cruds'],
    );
    final response = await transaction(
      [post(observation('Patient?identifier=urn:mrn|m1'))],
      token: obsOnly,
    );
    expect(response.statusCode, 403);
    expect(await storedObservations(), 0);
  });

  test(
      'a batch is left alone: conditional references are a transaction '
      'feature', () async {
    final response = await handler(
      testRequest(
        'POST',
        '/',
        body: jsonEncode({
          'resourceType': 'Bundle',
          'type': 'batch',
          'entry': [post(observation('Patient?_id=p1'))],
        }),
        authToken: admin,
      ),
    );
    expect(response.statusCode, 200);
  });
}
