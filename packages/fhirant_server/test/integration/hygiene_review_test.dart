import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-06 section 2 rows 21, 23, 24 and 26 at the HTTP surface.
void main() {
  late FhirAntDb db;
  late Handler handler;

  setUp(() async {
    final server = await createTestServer(devMode: true);
    db = server.db;
    handler = server.handler;
  });

  tearDown(() => db.close());

  Future<Map<String, dynamic>> json(Response r, [int? status]) async {
    final text = await r.readAsString();
    if (status != null) expect(r.statusCode, status, reason: text);
    return jsonDecode(text) as Map<String, dynamic>;
  }

  Future<void> save(Map<String, dynamic> resource) =>
      db.saveResource(fhir.Resource.fromJson(resource));

  final filtered = {
    'resourceType': 'ValueSet',
    'id': 'vs-filter',
    'url': 'http://example.org/vs/filter',
    'status': 'active',
    'compose': {
      'include': [
        {
          'system': 'http://example.org/cs',
          'filter': [
            {'property': 'concept', 'op': 'is-a', 'value': 'root'},
          ],
        },
      ],
    },
  };
  final excluded = {
    'resourceType': 'ValueSet',
    'id': 'vs-exclude',
    'url': 'http://example.org/vs/exclude',
    'status': 'active',
    'compose': {
      'include': [
        {
          'system': 'http://example.org/cs',
          'concept': [
            {'code': 'a'},
            {'code': 'b'},
          ],
        },
      ],
      'exclude': [
        {
          'system': 'http://example.org/cs',
          'concept': [
            {'code': 'b'},
          ],
        },
      ],
    },
  };
  Map<String, dynamic> observation(String id, String code) => {
        'resourceType': 'Observation',
        'id': id,
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://example.org/cs', 'code': code},
          ],
        },
      };

  group('JSON Patch arrays (row 21)', () {
    test('add with "-" appends through PATCH', () async {
      await save({
        'resourceType': 'Patient',
        'id': 'pj',
        'name': [
          {'family': 'A'},
        ],
      });
      final r = await handler(
        testRequest(
          'PATCH',
          '/Patient/pj',
          body: jsonEncode([
            {
              'op': 'add',
              'path': '/name/-',
              'value': {'family': 'B'},
            },
          ]),
          headers: {'content-type': 'application/json-patch+json'},
        ),
      );
      final body = await json(r, 200);
      expect((body['name'] as List).map((n) => n['family']), ['A', 'B']);
    });
  });

  group('FHIRPath Patch is refused (row 23)', () {
    final parameters = {
      'resourceType': 'Parameters',
      'parameter': [
        {
          'name': 'operation',
          'part': [
            {'name': 'type', 'valueCode': 'replace'},
            {'name': 'path', 'valueString': 'Patient.active'},
            {'name': 'value', 'valueBoolean': true},
          ],
        },
      ],
    };

    test('PATCH with a Parameters body is 415 not-supported', () async {
      await save({'resourceType': 'Patient', 'id': 'pf', 'active': false});
      final r = await handler(
        testRequest(
          'PATCH',
          '/Patient/pf',
          body: jsonEncode(parameters),
          headers: {'content-type': 'application/fhir+json'},
        ),
      );
      final body = await json(r, 415);
      expect(body['issue'][0]['code'], 'not-supported');
      final stored = await db.getResource(fhir.R4ResourceType.Patient, 'pf');
      expect((stored! as fhir.Patient).active?.valueBoolean, isFalse);
    });

    test('a Bundle PATCH entry with a Parameters body is 415', () async {
      await save({'resourceType': 'Patient', 'id': 'pb', 'active': false});
      final r = await handler(
        testRequest(
          'POST',
          '/',
          body: jsonEncode({
            'resourceType': 'Bundle',
            'type': 'batch',
            'entry': [
              {
                'request': {'method': 'PATCH', 'url': 'Patient/pb'},
                'resource': parameters,
              },
            ],
          }),
          headers: {'content-type': 'application/fhir+json'},
        ),
      );
      final body = await json(r, 200);
      expect(
        body['entry'][0]['response']['status'] as String,
        startsWith('415'),
      );
    });
  });

  group('a ValueSet compose this server cannot evaluate (row 24)', () {
    setUp(() async {
      await save(filtered);
      await save(excluded);
      await save(observation('oa', 'a'));
      await save(observation('ob', 'b'));
    });

    test(r'$expand refuses it with 422 not-supported', () async {
      final r = await handler(
        testRequest(
          'GET',
          r'/ValueSet/$expand?url=http://example.org/vs/filter',
        ),
      );
      final body = await json(r, 422);
      expect(body['issue'][0]['code'], 'not-supported');
      expect(body['issue'][0]['diagnostics'], contains('include.filter'));
    });

    test(r'$validate-code refuses it with 422 not-supported', () async {
      final r = await handler(
        testRequest(
          'GET',
          r'/ValueSet/$validate-code?url=http://example.org/vs/filter'
              '&system=http://example.org/cs&code=a',
        ),
      );
      final body = await json(r, 422);
      expect(body['issue'][0]['code'], 'not-supported');
    });

    test(':in refuses it with 400 not-supported', () async {
      final r = await handler(
        testRequest(
          'GET',
          '/Observation?code:in=http://example.org/vs/filter',
        ),
      );
      final body = await json(r, 400);
      expect(body['issue'][0]['code'], 'not-supported');
      expect(body['issue'][0]['diagnostics'], contains('include.filter'));
    });

    test(r'$expand and :in honour exclude.concept', () async {
      final expanded = await json(
        await handler(
          testRequest(
            'GET',
            r'/ValueSet/$expand?url=http://example.org/vs/exclude',
          ),
        ),
        200,
      );
      expect(
        (expanded['expansion']['contains'] as List).map((c) => c['code']),
        ['a'],
      );
      final searched = await json(
        await handler(
          testRequest(
            'GET',
            '/Observation?code:in=http://example.org/vs/exclude',
          ),
        ),
        200,
      );
      expect(
        (searched['entry'] as List).map((e) => e['resource']['id']),
        ['oa'],
      );
    });
  });

  group('_filter goes to the store as an id set (row 38)', () {
    setUp(() async {
      for (var i = 0; i < 6; i++) {
        await save({
          'resourceType': 'Patient',
          'id': 'f$i',
          'gender': i.isEven ? 'male' : 'female',
          'active': i < 4,
        });
      }
    });

    test('_summary=count and _count=0 count the filtered set', () async {
      final counted = await json(
        await handler(
          testRequest('GET', '/Patient?_filter=gender eq male&_summary=count'),
        ),
        200,
      );
      expect(counted['total'], 3);
      expect(counted['entry'], isNull);
      final zero = await json(
        await handler(
          testRequest(
            'GET',
            '/Patient?_filter=gender eq male and active eq true&_count=0',
          ),
        ),
        200,
      );
      expect(zero['total'], 2);
    });

    test('the filter ANDs with the other parameters and a client _id',
        () async {
      final body = await json(
        await handler(
          testRequest('GET', '/Patient?_filter=gender eq male&active=true'),
        ),
        200,
      );
      expect(body['total'], 2);
      expect(
        (body['entry'] as List).map((e) => e['resource']['id']),
        ['f0', 'f2'],
      );
      final narrowed = await json(
        await handler(
          testRequest('GET', '/Patient?_filter=gender eq male&_id=f2,f5'),
        ),
        200,
      );
      expect(narrowed['total'], 1);
      expect(narrowed['entry'][0]['resource']['id'], 'f2');
    });
  });

  group('the general search path (row 26)', () {
    test('an unknown parameter is ignored, not guessed at', () async {
      await save({
        'resourceType': 'Patient',
        'id': 'pu',
        'name': [
          {'family': 'Unique'},
        ],
      });
      // `:exact` takes the general path; `nonsense` has no definition.
      final body = await json(
        await handler(
          testRequest('GET', '/Patient?family:exact=Unique&nonsense=1'),
        ),
        200,
      );
      expect(body['total'], 1);
    });

    test('a value that ends in ":missing" is a value, not a modifier',
        () async {
      await save({
        'resourceType': 'Patient',
        'id': 'pm',
        'name': [
          {'family': 'Ends:missing'},
        ],
      });
      final body = await json(
        await handler(
          testRequest('GET', '/Patient?family:exact=Ends:missing'),
        ),
        200,
      );
      expect(body['total'], 1);
      expect(body['entry'][0]['resource']['id'], 'pm');
    });
  });
}
