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
/// `false` is answered. `true` and `both` are not supported and are refused
/// rather than ignored: ignoring would answer a search for contained
/// resources with the ordinary ones. The store does index contained
/// resources (under `#Type`, reached by chaining); no search answers from
/// them. Support was built and reverted on 2026-09-19 (REVIEW_DECISIONS.md).
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

  test('_contained=true and both are refused, under any Prefer', () async {
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
        expect(response.statusCode, 400, reason: '$value with $headers');
        final outcome =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        expect(
          ((outcome['issue'] as List).first as Map)['diagnostics'],
          contains('is not supported'),
        );
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

  test('a contained resource is indexed, but is not an ordinary match',
      () async {
    // The ordinary search (_contained=false, the default) must not return a
    // contained resource; the index holds it under `#Patient`.
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

    final contained = await server.db
        .customSelect(
          'SELECT count(*) AS n FROM string_search_parameters '
          "WHERE resource_type = '#Patient'",
        )
        .getSingle();
    expect(contained.read<int>('n'), greaterThan(0), reason: 'indexed');
  });
}
