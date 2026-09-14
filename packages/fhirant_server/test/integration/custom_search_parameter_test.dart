import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// Uploaded SearchParameters through the server: an admin posts US Core's
/// published race parameter (hl7.fhir.us.core#3.1.0
/// SearchParameter-us-core-race), the store indexes every later Patient by
/// it, `GET /Patient?race=` finds them, the CapabilityStatement lists it,
/// `$reindex` indexes what was stored before it, a definition the store
/// cannot index by is a 400, and a clinician may not define one. The
/// Patient's race extension is the one in US Core's published Patient
/// example (STU3.1.1 Patient-example.json, downloaded 2026-09-14).
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String admin;
  late String clinician;

  const raceUrl =
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-race';
  const racePath = '.extension.value.code';

  Map<String, dynamic> raceParameter({String status = 'active'}) => {
        'resourceType': 'SearchParameter',
        'id': 'us-core-race',
        'url': 'http://hl7.org/fhir/us/core/SearchParameter/us-core-race',
        'name': 'USCoreRace',
        'status': status,
        'description': 'Returns patients with a race extension matching the '
            'specified code.',
        'code': 'race',
        'base': ['Patient'],
        'type': 'token',
        'expression': "Patient.extension.where(url = '$raceUrl')$racePath",
      };

  Map<String, dynamic> patient(String id, {bool withRace = false}) => {
        'resourceType': 'Patient',
        'id': id,
        if (withRace)
          'extension': [
            {
              'extension': [
                {
                  'url': 'ombCategory',
                  'valueCoding': {
                    'system': 'urn:oid:2.16.840.1.113883.6.238',
                    'code': '2028-9',
                    'display': 'Asian',
                  },
                },
                {'url': 'text', 'valueString': 'Mixed'},
              ],
              'url': raceUrl,
            },
          ],
        'name': [
          {'family': 'Shaw'},
        ],
      };

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    admin = await issueTestToken(
      db,
      username: 'csp-admin',
      role: 'admin',
      scopes: ['system/*.*'],
    );
    clinician = await issueTestToken(
      db,
      username: 'csp-clin',
      scopes: ['user/*.cruds'],
    );
  });
  tearDown(() => db.close());

  Future<Response> send(
    String method,
    String path, {
    Object? body,
    String? token,
  }) async =>
      handler(
        testRequest(
          method,
          path,
          body: body == null ? null : jsonEncode(body),
          headers: {'content-type': 'application/fhir+json'},
          authToken: token ?? admin,
        ),
      );

  Future<Map<String, dynamic>> json(Response r, int status) async {
    final text = await r.readAsString();
    expect(r.statusCode, status, reason: text);
    return jsonDecode(text) as Map<String, dynamic>;
  }

  Future<List<String>> patientIds(String query) async {
    final bundle = await json(await send('GET', '/Patient?$query'), 200);
    return [
      for (final e in (bundle['entry'] as List?) ?? const [])
        ((e as Map<String, dynamic>)['resource'] as Map<String, dynamic>)['id']
            as String,
    ]..sort();
  }

  test('an uploaded parameter indexes later saves and is searchable', () async {
    await json(
      await send('PUT', '/SearchParameter/us-core-race', body: raceParameter()),
      201,
    );
    await json(
      await send(
        'PUT',
        '/Patient/mixed',
        body: patient('mixed', withRace: true),
      ),
      201,
    );
    await json(
      await send('PUT', '/Patient/plain', body: patient('plain')),
      201,
    );
    expect(await patientIds('race=2028-9'), ['mixed']);
    expect(await patientIds('race=9999-9'), isEmpty);
  });

  test('the CapabilityStatement lists it under Patient with its url', () async {
    await json(
      await send('PUT', '/SearchParameter/us-core-race', body: raceParameter()),
      201,
    );
    final cs = await json(await send('GET', '/metadata'), 200);
    final rest = (cs['rest'] as List).first as Map<String, dynamic>;
    final patientRes = (rest['resource'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((r) => r['type'] == 'Patient');
    final race = (patientRes['searchParam'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((p) => p['name'] == 'race');
    expect(race['type'], 'token');
    expect(
      race['definition'],
      'http://hl7.org/fhir/us/core/SearchParameter/us-core-race',
    );
  });

  test(r'$reindex indexes what was stored before the parameter', () async {
    await json(
      await send(
        'PUT',
        '/Patient/early',
        body: patient('early', withRace: true),
      ),
      201,
    );
    await json(
      await send('PUT', '/SearchParameter/us-core-race', body: raceParameter()),
      201,
    );
    expect(await patientIds('race=2028-9'), isEmpty);
    final kickoff = await send('POST', r'/$reindex');
    expect(kickoff.statusCode, 202, reason: await kickoff.readAsString());
    expect(kickoff.headers['content-location'], endsWith(r'$reindex-status'));
    Response status;
    do {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      status = await send('GET', r'/$reindex-status');
    } while (status.statusCode == 202);
    final outcome = await json(status, 200);
    expect(
      ((outcome['issue'] as List).first as Map)['diagnostics'],
      contains('Reindexed 2 resources'),
    );
    expect(await patientIds('race=2028-9'), ['early']);
  });

  test('a definition the store cannot index by is a 400 OperationOutcome',
      () async {
    final r = await send(
      'PUT',
      '/SearchParameter/us-core-race',
      body: {...raceParameter(), 'type': 'composite'},
    );
    final outcome = await json(r, 400);
    expect(outcome['resourceType'], 'OperationOutcome');
    expect(
      ((outcome['issue'] as List).first as Map)['diagnostics'],
      contains('composite'),
    );
    expect(
      (await send('GET', '/SearchParameter/us-core-race')).statusCode,
      404,
    );
    // In a transaction Bundle the entry fails the same way.
    final bundle = await send(
      'POST',
      '/',
      body: {
        'resourceType': 'Bundle',
        'type': 'transaction',
        'entry': [
          {
            'resource': {...raceParameter(), 'expression': 'Patient.('},
            'request': {'method': 'PUT', 'url': 'SearchParameter/us-core-race'},
          },
        ],
      },
    );
    expect(bundle.statusCode, 400, reason: await bundle.readAsString());
  });

  test('defining or deleting one is system authority', () async {
    final r = await send(
      'PUT',
      '/SearchParameter/us-core-race',
      body: raceParameter(),
      token: clinician,
    );
    await json(r, 403);
    await json(
      await send('PUT', '/SearchParameter/us-core-race', body: raceParameter()),
      201,
    );
    final d = await send(
      'DELETE',
      '/SearchParameter/us-core-race',
      token: clinician,
    );
    await json(d, 403);
    expect(
      (await send('DELETE', '/SearchParameter/us-core-race')).statusCode,
      204,
    );
    expect(await patientIds('race=2028-9'), isEmpty);
  });
}
