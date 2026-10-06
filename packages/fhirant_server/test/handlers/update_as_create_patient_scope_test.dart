import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../integration/test_helpers.dart';

/// REVIEW-2026-10-06 finding 7 (probe P4): under a patient scope, `PUT
/// /Observation/new1` of the patient's own Observation was 403 over REST
/// (the membership check ran on a resource with no index rows yet) and 201
/// as a Bundle entry. R4B http.html "Update as Create", which the
/// CapabilityStatement advertises as `updateCreate: true`: the REST route
/// now applies the Bundle's rule, the body must be in the compartment.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String patient;

  String observation(String id, String subject) => jsonEncode({
        'resourceType': 'Observation',
        'id': id,
        'status': 'final',
        'code': {'text': 'x'},
        'subject': {'reference': 'Patient/$subject'},
      });

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    final admin = await issueTestToken(
      db,
      username: 'adm',
      role: 'admin',
      scopes: ['system/*.*'],
    );
    for (final id in ['pat1', 'pat2']) {
      await handler(
        testRequest(
          'PUT',
          '/Patient/$id',
          body: jsonEncode({'resourceType': 'Patient', 'id': id}),
          authToken: admin,
        ),
      );
    }
    await handler(
      testRequest(
        'PUT',
        '/Observation/theirs',
        body: observation('theirs', 'pat2'),
        authToken: admin,
      ),
    );
    patient = await issueTestToken(
      db,
      username: 'patu',
      role: 'readonly',
      scopes: ['patient/*.*'],
      patientId: 'pat1',
    );
  });

  tearDown(() => db.close());

  Future<Response> put(String id, String body) async => handler(
        testRequest('PUT', '/Observation/$id', body: body, authToken: patient),
      );

  test('update-as-create of a resource in the compartment is 201', () async {
    final response = await put('new1', observation('new1', 'pat1'));
    expect(response.statusCode, 201, reason: await response.readAsString());
  });

  test('update-as-create of a resource outside the compartment is 403',
      () async {
    final response = await put('new2', observation('new2', 'pat2'));
    expect(response.statusCode, 403);
  });

  test("an update of another patient's stored resource is still 403", () async {
    final response = await put('theirs', observation('theirs', 'pat1'));
    expect(response.statusCode, 403);
  });

  test('the REST route and a Bundle entry now agree', () async {
    final bundle = jsonEncode({
      'resourceType': 'Bundle',
      'type': 'transaction',
      'entry': [
        {
          'resource': jsonDecode(observation('new3', 'pat1')),
          'request': {'method': 'PUT', 'url': 'Observation/new3'},
        },
      ],
    });
    final viaBundle = await handler(
      testRequest('POST', '/', body: bundle, authToken: patient),
    );
    expect(viaBundle.statusCode, 200);
    final viaRest = await put('new4', observation('new4', 'pat1'));
    expect(viaRest.statusCode, 201);
  });
}
