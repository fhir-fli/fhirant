import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// `_filter` through the HTTP endpoint, against the real database.
///
/// R4 3.1.3's own worked example is
/// `Observation?_filter=code eq http://loinc.org|1234-5 and subject.name co
/// "peter"`, and the point of the parameter is the combination search that
/// the ordinary parameters cannot express.
void main() {
  late FhirAntDb testDb;
  late Handler handler;
  late String token;

  setUp(() async {
    final server = await createTestServer();
    testDb = server.db;
    handler = server.handler;
    token = generateTestToken(scopes: ['user/*.rs']);

    await testDb.saveResource(
      fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'okello',
        'name': [
          {'family': 'Okello'},
        ],
        'gender': 'female',
        'birthDate': '1980-05-05',
      }),
    );
    await testDb.saveResource(
      fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'okot',
        'name': [
          {'family': 'Okot'},
        ],
        'gender': 'male',
        'birthDate': '1990-01-01',
      }),
    );
  });

  tearDown(() async {
    await testDb.close();
  });

  Future<Response> search(String query) async => handler(
        testRequest('GET', '/Patient?$query', authToken: token),
      );

  Future<List<String>> ids(Response response) async {
    final bundle =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    return ((bundle['entry'] as List?) ?? [])
        .map((entry) => (entry as Map)['resource'] as Map)
        .map((resource) => resource['id'] as String)
        .toList()
      ..sort();
  }

  test('a filter narrows the set', () async {
    final response = await search(
      '_filter=${Uri.encodeQueryComponent('family co "kel"')}',
    );
    expect(response.statusCode, 200);
    expect(await ids(response), ['okello']);
  });

  test('and, or and not all reach the database', () async {
    expect(
      await ids(
        await search(
          '_filter=${Uri.encodeQueryComponent(
            'gender eq female and birthdate lt 1985-01-01',
          )}',
        ),
      ),
      ['okello'],
    );
    expect(
      await ids(
        await search(
          '_filter=${Uri.encodeQueryComponent(
            'family sw "Okello" or family sw "Okot"',
          )}',
        ),
      ),
      ['okello', 'okot'],
    );
    expect(
      await ids(
        await search(
          '_filter=${Uri.encodeQueryComponent('not(gender eq female)')}',
        ),
      ),
      ['okot'],
    );
  });

  test('a filter is ANDed with the ordinary parameters', () async {
    // gender=male alone is okot; the filter alone is okello; together, empty.
    final response = await search(
      'gender=male&_filter=${Uri.encodeQueryComponent('family co "kel"')}',
    );
    expect(response.statusCode, 200);
    expect(await ids(response), isEmpty);
  });

  test('a filter matching nothing returns an empty searchset', () async {
    final response = await search(
      '_filter=${Uri.encodeQueryComponent('family co "zzz"')}',
    );
    expect(response.statusCode, 200);
    final bundle =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(bundle['type'], 'searchset');
    expect(bundle['entry'], anyOf(isNull, isEmpty));
  });

  test('an operator this server cannot answer is a 400, not a result',
      () async {
    final response = await search(
      '_filter=${Uri.encodeQueryComponent('family eq "Okello"')}',
    );
    expect(response.statusCode, 400);
    final outcome =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(outcome['resourceType'], 'OperationOutcome');
    expect(
      ((outcome['issue'] as List).first as Map)['diagnostics'],
      contains('case-insensitively'),
    );
  });

  test('a filter that does not parse is a 400 naming the offset', () async {
    final response = await search(
      '_filter=${Uri.encodeQueryComponent('family like "Okello"')}',
    );
    expect(response.statusCode, 400);
    final outcome =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(
      ((outcome['issue'] as List).first as Map)['diagnostics'],
      contains('offset'),
    );
  });

  test('_filter is no longer refused under Prefer: handling=strict', () async {
    final response = await handler(
      testRequest(
        'GET',
        '/Patient?_filter=${Uri.encodeQueryComponent('family co "kel"')}',
        authToken: token,
        headers: {'Prefer': 'handling=strict'},
      ),
    );
    expect(response.statusCode, 200);
    expect(await ids(response), ['okello']);
  });
}
