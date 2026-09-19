import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-17 C2. The CapabilityStatement claimed
/// `conditionalUpdate: true` and `PUT /Patient?identifier=…` was a 404.
///
/// R4B http.html 3.1.0.4.3, section read whole 2026-09-18, the five rows
/// verbatim: "No matches, no id provided: The server creates the resource";
/// "No matches, id provided: The server treats the interaction as an Update
/// as Create interaction"; "One Match, no resource id provided OR (resource
/// id provided and it matches the found resource): The server performs the
/// update against the matching resource"; "One Match, resource id provided
/// but does not match resource found: The server returns a 400 Bad Request
/// error"; "Multiple matches: The server returns a 412 Precondition Failed
/// error". Each row over REST, and the update row inside a transaction.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;
  late Directory exportDir;

  setUp(() async {
    exportDir = await Directory.systemTemp.createTemp('cond-update');
    final server = await createTestServer(exportDir: exportDir.path);
    db = server.db;
    handler = server.handler;
    token = await issueTestToken(
      db,
      username: 'admin',
      role: 'admin',
      scopes: ['system/*.*'],
    );
  });

  tearDown(() async {
    await db.close();
    await exportDir.delete(recursive: true);
  });

  Map<String, dynamic> patient(String mrn, {String? id, String? family}) => {
        'resourceType': 'Patient',
        if (id != null) 'id': id,
        'identifier': [
          {'system': 'http://mrn.example.org', 'value': mrn},
        ],
        if (family != null)
          'name': [
            {'family': family},
          ],
      };

  Future<Response> put(String url, Map<String, dynamic> body) async => handler(
        testRequest(
          'PUT',
          url,
          authToken: token,
          headers: {'content-type': 'application/fhir+json'},
          body: jsonEncode(body),
        ),
      );

  Future<Map<String, dynamic>> json(Response r, int status) async {
    final text = await r.readAsString();
    expect(r.statusCode, status, reason: text);
    return jsonDecode(text) as Map<String, dynamic>;
  }

  const byMrn = '/Patient?identifier=http://mrn.example.org|42';

  test('no matches, no id: the server creates the resource', () async {
    final created = await json(await put(byMrn, patient('42')), 201);
    expect(created['id'], isNotNull);
    expect(
      await db.getResource(
        fhir.R4ResourceType.Patient,
        created['id'] as String,
      ),
      isNotNull,
    );
  });

  test('no matches, id provided: update as create under that id', () async {
    final created =
        await json(await put(byMrn, patient('42', id: 'mine')), 201);
    expect(created['id'], 'mine');
  });

  test('one match, no id: the match is updated', () async {
    await db.saveResource(
      fhir.Patient.fromJson(patient('42', id: 'p42', family: 'Before')),
    );
    final updated =
        await json(await put(byMrn, patient('42', family: 'After')), 200);
    expect(updated['id'], 'p42');
    expect(updated['meta']['versionId'], '2');
    final stored = await db.getResource(fhir.R4ResourceType.Patient, 'p42');
    expect(
      (stored! as fhir.Patient).name!.single.family!.valueString,
      'After',
    );
  });

  test('one match, the same id: the match is updated', () async {
    await db.saveResource(fhir.Patient.fromJson(patient('42', id: 'p42')));
    final updated = await json(
      await put(byMrn, patient('42', id: 'p42', family: 'After')),
      200,
    );
    expect(updated['id'], 'p42');
  });

  test('one match, a different id: 400', () async {
    await db.saveResource(fhir.Patient.fromJson(patient('42', id: 'p42')));
    final outcome =
        await json(await put(byMrn, patient('42', id: 'other')), 400);
    expect(outcome['resourceType'], 'OperationOutcome');
    expect(jsonEncode(outcome), contains('p42'));
    expect(
      await db.getResource(fhir.R4ResourceType.Patient, 'other'),
      isNull,
    );
  });

  test('multiple matches: 412', () async {
    await db.saveResource(fhir.Patient.fromJson(patient('42', id: 'a')));
    await db.saveResource(fhir.Patient.fromJson(patient('42', id: 'b')));
    final outcome = await json(await put(byMrn, patient('42')), 412);
    expect(
      (outcome['issue'] as List).first['code'],
      'multiple-matches',
    );
  });

  test('no criteria: 400', () async {
    await json(await put('/Patient', patient('42')), 400);
  });

  test('the criteria are searched as a search is', () async {
    final outcome = await json(
      await put('/Patient?identifier:banana=42', patient('42')),
      400,
    );
    expect((outcome['issue'] as List).first['code'], 'not-supported');
  });

  test('inside a transaction, the same rows', () async {
    await db.saveResource(
      fhir.Patient.fromJson(patient('42', id: 'p42', family: 'Before')),
    );
    final r = await handler(
      testRequest(
        'POST',
        '/',
        authToken: token,
        headers: {'content-type': 'application/fhir+json'},
        body: jsonEncode({
          'resourceType': 'Bundle',
          'type': 'transaction',
          'entry': [
            {
              'resource': patient('42', family: 'After'),
              'request': {
                'method': 'PUT',
                'url': 'Patient?identifier=http://mrn.example.org|42',
              },
            },
            {
              'resource': patient('7', family: 'New'),
              'request': {
                'method': 'PUT',
                'url': 'Patient?identifier=http://mrn.example.org|7',
              },
            },
          ],
        }),
      ),
    );
    final b = await json(r, 200);
    final statuses = (b['entry'] as List)
        .map((e) => (e as Map)['response']['status'])
        .toList();
    expect(statuses, ['200', '201']);
    final stored = await db.getResource(fhir.R4ResourceType.Patient, 'p42');
    expect(
      (stored! as fhir.Patient).name!.single.family!.valueString,
      'After',
    );
    expect(
      await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'identifier': ['http://mrn.example.org|7'],
        },
      ),
      hasLength(1),
    );
  });

  test('a patient-scoped token matches only inside its compartment', () async {
    // Two patients share the MRN; the caller may only see one, so for the
    // caller there is one match and it is the one updated.
    await db.saveResource(fhir.Patient.fromJson(patient('42', id: 'mine')));
    await db.saveResource(fhir.Patient.fromJson(patient('42', id: 'theirs')));
    final scoped = await issueTestToken(
      db,
      username: 'patient-mine',
      scopes: ['patient/*.*'],
      patientId: 'mine',
    );
    final r = await handler(
      testRequest(
        'PUT',
        byMrn,
        authToken: scoped,
        headers: {'content-type': 'application/fhir+json'},
        body: jsonEncode(patient('42', family: 'Renamed')),
      ),
    );
    final updated = await json(r, 200);
    expect(updated['id'], 'mine');
  });
}
