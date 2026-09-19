import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:test/test.dart';

import 'test_helpers.dart';

/// `_contained`, per R4 search.html's summary table:
///
/// > _contained — Whether to return resources contained in other resources in
/// > the search matches. true | false | both (false is default)
/// > _containedType — If returning contained resources, whether to return the
/// > contained or container resources. container | contained
///
/// Measured 2026-09-02: saving an Observation carrying a contained Patient
/// stores the Observation and nothing else, and the contained Patient is not
/// indexed. So `false` is answered, and `true`/`both` are refused rather than
/// answered with container matches that would say the search covered them.
void main() {
  test('_contained=false is answered, being the default behaviour', () async {
    final server = await createTestServer();
    final token = await issueTestToken(server.db, scopes: ['user/*.cruds']);
    await server.db.saveResource(fhir.Patient(id: 'p-1'.toFhirString));

    for (final headers in [
      <String, String>{},
      {'Prefer': 'handling=strict'},
    ]) {
      final response = await server.handler(
        testRequest(
          'GET',
          '/Patient?_contained=false',
          authToken: token,
          headers: headers,
        ),
      );
      expect(response.statusCode, 200, reason: 'headers: $headers');
      final bundle =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect((bundle['entry'] as List?) ?? [], hasLength(1));
    }
  });

  test('_contained=true and both are answered, under any Prefer', () async {
    // They were refused as "not indexed" until REVIEW-2026-09-17 Q8; the
    // contained cases themselves are in contained_search_test.dart. Here
    // nothing is contained: `true` finds nothing, `both` finds the patient.
    final server = await createTestServer();
    final token = await issueTestToken(server.db, scopes: ['user/*.cruds']);
    await server.db.saveResource(fhir.Patient(id: 'p-1'.toFhirString));

    for (final value in ['true', 'both']) {
      for (final headers in [
        <String, String>{},
        {'Prefer': 'handling=lenient'},
        {'Prefer': 'handling=strict'},
      ]) {
        final response = await server.handler(
          testRequest(
            'GET',
            '/Patient?_contained=$value',
            authToken: token,
            headers: headers,
          ),
        );
        expect(response.statusCode, 200, reason: '$value with $headers');
        final bundle =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        expect(bundle['total'], value == 'true' ? 0 : 1);
      }
    }
  });

  test('a value outside true|false|both is refused', () async {
    final server = await createTestServer();
    final token = await issueTestToken(server.db, scopes: ['user/*.cruds']);

    final response = await server.handler(
      testRequest('GET', '/Patient?_contained=maybe', authToken: token),
    );
    expect(response.statusCode, 400);
    final outcome =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(
      ((outcome['issue'] as List).first as Map)['diagnostics'],
      contains('must be true, false or both'),
    );
  });

  test('_containedType is checked, and cannot change a false answer', () async {
    final server = await createTestServer();
    final token = await issueTestToken(server.db, scopes: ['user/*.cruds']);
    await server.db.saveResource(fhir.Patient(id: 'p-1'.toFhirString));

    final bad = await server.handler(
      testRequest(
        'GET',
        '/Patient?_containedType=neither',
        authToken: token,
      ),
    );
    expect(bad.statusCode, 400);

    // With nothing contained returned, container/contained cannot change the
    // result, so it is not an error on its own.
    final fine = await server.handler(
      testRequest(
        'GET',
        '/Patient?_contained=false&_containedType=container',
        authToken: token,
      ),
    );
    expect(fine.statusCode, 200);
  });

  test('a contained resource is not a normal match, and is a contained one',
      () async {
    // R4B search.html 3.1.1.5.5, read whole 2026-09-19, verbatim: "By
    // default, search results only include resources that are not
    // contained in other resources." The contained index (fhir_db schema 7)
    // files it under `#Patient`, where searchContainedIds finds it
    // (REVIEW-2026-09-17 Q8).
    final server = await createTestServer();
    await server.db.saveResource(
      fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': 'obs-1',
        'status': 'final',
        'code': {'text': 'weight'},
        'contained': [
          {
            'resourceType': 'Patient',
            'id': 'inner',
            'name': [
              {'family': 'Containedsson'},
            ],
          },
        ],
        'subject': {'reference': '#inner'},
      }),
    );

    final patients = await server.db.search(
      resourceType: fhir.R4ResourceType.Patient,
      searchParameters: const {},
    );
    expect(patients, isEmpty);
    expect(
      await server.db.searchContainedIds(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'family': ['Containedsson'],
        },
      ),
      {'Observation/obs-1#inner'},
    );
  });
}
