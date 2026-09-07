import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// The all-types search context, R4B search.html 3.1.1.2 (read whole
/// 2026-09-06): "All resource types: GET [base]?parameter(s) (parameters
/// common to all types). If the _type parameter is included, all other search
/// parameters SHALL be common to all provided types. If _type is not included,
/// all parameters SHALL be common to all resource types."
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    token = generateTestToken(scopes: ['user/*.cruds']);
    for (final id in ['p1', 'p2', 'p3']) {
      await db.saveResource(
        fhir.Patient.fromJson({
          'resourceType': 'Patient',
          'id': id,
          'gender': 'female',
        }),
      );
    }
    for (final id in ['o1', 'o2']) {
      await db.saveResource(
        fhir.Observation.fromJson({
          'resourceType': 'Observation',
          'id': id,
          'status': 'final',
          'code': {
            'coding': [
              {'system': 'http://loinc.org', 'code': '8867-4'},
            ],
          },
          'subject': {'reference': 'Patient/p1'},
        }),
      );
    }
    await db.saveResource(
      fhir.Condition.fromJson({
        'resourceType': 'Condition',
        'id': 'c1',
        'subject': {'reference': 'Patient/p2'},
      }),
    );
  });
  tearDown(() async => db.close());

  Future<Response> get(String path, {Map<String, String>? headers}) async =>
      handler(testRequest('GET', path, authToken: token, headers: headers));

  Future<Response> post(String body) async => handler(
        testRequest(
          'POST',
          '/_search',
          authToken: token,
          body: body,
          headers: {'content-type': 'application/x-www-form-urlencoded'},
        ),
      );

  Future<Map<String, dynamic>> bundle(Response response) async {
    expect(response.statusCode, 200);
    return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
  }

  List<String> refs(Map<String, dynamic> b) => ((b['entry'] as List?) ?? [])
      .map((e) => '${e['resource']['resourceType']}/${e['resource']['id']}')
      .toList();

  String? link(Map<String, dynamic> b, String relation) {
    for (final l in (b['link'] as List?) ?? []) {
      if ((l as Map)['relation'] == relation) return l['url'] as String;
    }
    return null;
  }

  group('the common-parameter rule', () {
    test('a parameter one of the _type types lacks is 400', () async {
      final response = await get('/?_type=Patient,Observation&gender=female');
      expect(response.statusCode, 400);
      final body = await response.readAsString();
      expect(body, contains('gender'));
      expect(body, contains('Observation'));
    });

    test('a parameter every _type type has is accepted', () async {
      final b = await bundle(
        await get('/?_type=Observation,Condition&subject=Patient/p1'),
      );
      expect(refs(b), ['Observation/o1', 'Observation/o2']);
    });

    test('without _type only the Resource-level parameters are accepted',
        () async {
      final refused = await get('/?gender=female');
      expect(refused.statusCode, 400);
      final b = await bundle(await get('/?_id=p1'));
      expect(refs(b), ['Patient/p1']);
    });

    test('an unknown resource type in _type is 400', () async {
      expect((await get('/?_type=NotAType')).statusCode, 400);
    });

    test('_sort on a parameter one type lacks is 400', () async {
      expect(
        (await get('/?_type=Patient,Observation&_sort=gender')).statusCode,
        400,
      );
    });
  });

  group('one result set across the types', () {
    test('without _type, every stored type, in type order', () async {
      final b = await bundle(await get('/?_lastUpdated=ge2000-01-01'));
      expect(b['total'], 6);
      expect(refs(b), [
        'Condition/c1',
        'Observation/o1',
        'Observation/o2',
        'Patient/p1',
        'Patient/p2',
        'Patient/p3',
      ]);
    });

    test('_count bounds the bundle, not each type', () async {
      final b = await bundle(await get('/?_type=Observation,Patient&_count=3'));
      expect(b['total'], 5);
      expect(refs(b), ['Observation/o1', 'Observation/o2', 'Patient/p1']);
      expect(link(b, 'next'), contains('_offset=3'));
      final second = await bundle(
        await get('/?_type=Observation,Patient&_count=3&_offset=3'),
      );
      expect(refs(second), ['Patient/p2', 'Patient/p3']);
      expect(link(second, 'next'), isNull);
      expect(link(second, 'previous'), contains('_offset=0'));
    });

    test('the self link keeps _type and drops nothing that was used', () async {
      final b = await bundle(await get('/?_type=Patient&_id=p1&_count=5'));
      final self = link(b, 'self')!;
      expect(self, contains('_type=Patient'));
      expect(self, contains('_id=p1'));
    });

    test('_summary=count and _count=0 give the total across types', () async {
      final b = await bundle(await get('/?_type=Patient,Condition&_count=0'));
      expect(b['total'], 4);
      expect(b['entry'], isNull);
    });

    test('_total=none pages by the links without a total', () async {
      final b = await bundle(
        await get('/?_type=Patient&_count=2&_total=none'),
      );
      expect(b['total'], isNull);
      expect(refs(b), hasLength(2));
    });
  });

  group('POST /_search', () {
    test('body and URL parameters merge; URL wins', () async {
      final b = await bundle(await post('_type=Patient&_id=p2'));
      expect(refs(b), ['Patient/p2']);
    });

    test('is refused the same way for a non-common parameter', () async {
      expect(
        (await post('_type=Patient,Condition&gender=female')).statusCode,
        400,
      );
    });
  });

  test('a bare GET / is still the welcome page', () async {
    final response = await get('/');
    expect(response.statusCode, 200);
    expect(response.headers['content-type'], contains('text/plain'));
  });
}
