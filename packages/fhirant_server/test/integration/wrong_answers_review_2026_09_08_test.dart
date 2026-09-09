import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// The "wrong answers" of REVIEW-2026-09-08.md §2 (rows 21–29) and the
/// transaction processing order of REVIEW-2026-09-06 row 16, as regression
/// tests. Each expectation is the specification's; the probes that failed
/// against the old code are in `tool/review_2026-09-08/probes/OUTPUT.txt`.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;
  late Directory exportDir;

  setUp(() async {
    exportDir = await Directory.systemTemp.createTemp('wrong-2026-09-08');
    final server = await createTestServer(exportDir: exportDir.path);
    db = server.db;
    handler = server.handler;
    token = await issueTestToken(
      db,
      username: 'admin',
      role: 'admin',
      scopes: ['system/*.*'],
    );
    await db.saveResource(
      fhir.Patient(
        id: 'p1'.toFhirString,
        name: [fhir.HumanName(family: 'One'.toFhirString)],
      ),
    );
    await db.saveResource(
      fhir.Patient(
        id: 'p2'.toFhirString,
        name: [fhir.HumanName(family: 'Two'.toFhirString)],
      ),
    );
  });

  tearDown(() async {
    await db.close();
    await exportDir.delete(recursive: true);
  });

  Future<Response> send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) async =>
      await handler(
        testRequest(
          method,
          path,
          body: body == null
              ? null
              : body is String
                  ? body
                  : jsonEncode(body),
          authToken: token,
          headers: {'content-type': 'application/fhir+json', ...?headers},
        ),
      );

  Future<Map<String, dynamic>> json(Response r, [int? status]) async {
    final text = await r.readAsString();
    if (status != null) expect(r.statusCode, status, reason: text);
    return jsonDecode(text) as Map<String, dynamic>;
  }

  Map<String, dynamic> tx(
    List<Map<String, dynamic>> entries, {
    String type = 'transaction',
  }) =>
      {'resourceType': 'Bundle', 'type': type, 'entry': entries};

  group('row 21: create ignores a client-supplied id', () {
    test('POST /Patient with id p2 creates a new Patient, p2 untouched',
        () async {
      final r = await send(
        'POST',
        '/Patient',
        body: {
          'resourceType': 'Patient',
          'id': 'p2',
          'name': [
            {'family': 'Hijack'},
          ],
        },
      );
      final created = await json(r, 201);
      expect(created['id'], isNot('p2'));
      final p2 = (await db.getResource(fhir.R4ResourceType.Patient, 'p2'))!
          as fhir.Patient;
      expect(p2.name?.first.family?.valueString, 'Two');
      expect(p2.meta?.versionId?.valueString, '1');
    });
    test('a Bundle POST entry with an id is a create, not an update', () async {
      final r = await send(
        'POST',
        '/',
        body: tx([
          {
            'resource': {
              'resourceType': 'Patient',
              'id': 'p2',
              'name': [
                {'family': 'Hijack'},
              ],
            },
            'request': {'method': 'POST', 'url': 'Patient'},
          },
        ]),
      );
      final b = await json(r, 200);
      final entry = (b['entry'] as List).first as Map<String, dynamic>;
      expect((entry['resource'] as Map)['id'], isNot('p2'));
      expect(await db.getResourceCount(fhir.R4ResourceType.Patient), 3);
    });
  });

  group('row 26: Location carries the version', () {
    test('POST', () async {
      final r =
          await send('POST', '/Patient', body: {'resourceType': 'Patient'});
      expect(r.statusCode, 201);
      expect(
        r.headers['location'],
        matches(RegExp(r'^/Patient/[^/]+/_history/1$')),
      );
    });
    test('a transaction POST entry', () async {
      final r = await send(
        'POST',
        '/',
        body: tx([
          {
            'resource': {'resourceType': 'Patient'},
            'request': {'method': 'POST', 'url': 'Patient'},
          },
        ]),
      );
      final b = await json(r, 200);
      final response = ((b['entry'] as List).first as Map)['response'] as Map;
      expect(response['location'], matches(RegExp(r'/_history/1$')));
    });
  });

  group('row 22: If-Match', () {
    test('PATCH honours a stale If-Match with 412', () async {
      final r = await send(
        'PATCH',
        '/Patient/p1',
        body: [
          {'op': 'replace', 'path': '/name/0/family', 'value': 'Patched'},
        ],
        headers: {
          'content-type': 'application/json-patch+json',
          'if-match': 'W/"99"',
        },
      );
      expect(r.statusCode, 412, reason: await r.readAsString());
      final p1 = (await db.getResource(fhir.R4ResourceType.Patient, 'p1'))!
          as fhir.Patient;
      expect(p1.name?.first.family?.valueString, 'One');
    });
    test('PATCH with the current If-Match succeeds', () async {
      final r = await send(
        'PATCH',
        '/Patient/p1',
        body: [
          {'op': 'replace', 'path': '/name/0/family', 'value': 'Patched'},
        ],
        headers: {
          'content-type': 'application/json-patch+json',
          'if-match': 'W/"1"',
        },
      );
      expect(r.statusCode, 200, reason: await r.readAsString());
    });
    test('a Bundle PUT with a stale ifMatch fails the transaction with 412',
        () async {
      final r = await send(
        'POST',
        '/',
        body: tx([
          {
            'resource': {
              'resourceType': 'Patient',
              'id': 'p1',
              'name': [
                {'family': 'Stale'},
              ],
            },
            'request': {
              'method': 'PUT',
              'url': 'Patient/p1',
              'ifMatch': 'W/"99"',
            },
          },
        ]),
      );
      expect(r.statusCode, 412, reason: await r.readAsString());
      final p1 = (await db.getResource(fhir.R4ResourceType.Patient, 'p1'))!
          as fhir.Patient;
      expect(p1.name?.first.family?.valueString, 'One');
    });
    test('a Bundle PUT with ifMatch on a resource that does not exist is 412',
        () async {
      final r = await send(
        'POST',
        '/',
        body: tx([
          {
            'resource': {'resourceType': 'Patient', 'id': 'nope'},
            'request': {
              'method': 'PUT',
              'url': 'Patient/nope',
              'ifMatch': 'W/"1"',
            },
          },
        ]),
      );
      expect(r.statusCode, 412, reason: await r.readAsString());
      expect(await db.getResource(fhir.R4ResourceType.Patient, 'nope'), isNull);
    });
  });

  group('row 23: JSON Patch replace', () {
    test('of an absent member fails (RFC 6902 4.3)', () async {
      final r = await send(
        'PATCH',
        '/Patient/p1',
        body: [
          {'op': 'replace', 'path': '/gender', 'value': 'female'},
        ],
        headers: {'content-type': 'application/json-patch+json'},
      );
      expect(r.statusCode, 400, reason: await r.readAsString());
    });
    test('of a present member succeeds', () async {
      final r = await send(
        'PATCH',
        '/Patient/p1',
        body: [
          {'op': 'replace', 'path': '/name/0/family', 'value': 'Replaced'},
        ],
        headers: {'content-type': 'application/json-patch+json'},
      );
      expect(r.statusCode, 200, reason: await r.readAsString());
    });
  });

  group('row 24: Bundle entries with a query', () {
    test('a batch GET with a search URL is answered with a searchset',
        () async {
      final r = await send(
        'POST',
        '/',
        body: tx(
          [
            {
              'request': {'method': 'GET', 'url': 'Patient?family=One'},
            },
          ],
          type: 'batch',
        ),
      );
      final b = await json(r, 200);
      final entry = (b['entry'] as List).first as Map<String, dynamic>;
      expect((entry['response'] as Map)['status'], '200');
      final set = entry['resource'] as Map<String, dynamic>;
      expect(set['type'], 'searchset');
      expect(set['total'], 1);
      expect(
        ((set['entry'] as List).first as Map)['resource']['id'],
        'p1',
      );
    });
    test('a type-level GET with no query is the search of the type', () async {
      final r = await send(
        'POST',
        '/',
        body: tx(
          [
            {
              'request': {'method': 'GET', 'url': 'Patient'},
            },
          ],
          type: 'batch',
        ),
      );
      final b = await json(r, 200);
      final set = ((b['entry'] as List).first as Map)['resource'] as Map;
      expect(set['total'], 2);
    });
    test('a conditional DELETE entry deletes the matches, bounded', () async {
      final r = await send(
        'POST',
        '/',
        body: tx([
          {
            'request': {'method': 'DELETE', 'url': 'Patient?family=Two'},
          },
        ]),
      );
      final b = await json(r, 200);
      final response = ((b['entry'] as List).first as Map)['response'] as Map;
      expect(response['status'], '204');
      expect(await db.getResource(fhir.R4ResourceType.Patient, 'p2'), isNull);
      expect(
        await db.getResource(fhir.R4ResourceType.Patient, 'p1'),
        isNotNull,
      );
    });
  });

  group('REVIEW-2026-09-06 row 16: transaction processing order', () {
    test('a forward urn:uuid to a later POST is resolved', () async {
      final r = await send(
        'POST',
        '/',
        body: tx([
          {
            'fullUrl': 'urn:uuid:obs',
            'resource': {
              'resourceType': 'Observation',
              'status': 'final',
              'code': {'text': 'weight'},
              'subject': {'reference': 'urn:uuid:pat'},
            },
            'request': {'method': 'POST', 'url': 'Observation'},
          },
          {
            'fullUrl': 'urn:uuid:pat',
            'resource': {'resourceType': 'Patient'},
            'request': {'method': 'POST', 'url': 'Patient'},
          },
        ]),
      );
      final b = await json(r, 200);
      final entries = b['entry'] as List;
      final obs = (entries[0] as Map)['resource'] as Map;
      final pat = (entries[1] as Map)['resource'] as Map;
      expect(
        (obs['subject'] as Map)['reference'],
        'Patient/${pat['id']}',
        reason: 'the response keeps the request order and the reference '
            'names the created Patient',
      );
    });
    test('a GET in a transaction sees the POST that follows it', () async {
      final r = await send(
        'POST',
        '/',
        body: tx([
          {
            'request': {'method': 'GET', 'url': 'Patient?family=Later'},
          },
          {
            'resource': {
              'resourceType': 'Patient',
              'name': [
                {'family': 'Later'},
              ],
            },
            'request': {'method': 'POST', 'url': 'Patient'},
          },
        ]),
      );
      final b = await json(r, 200);
      final set = ((b['entry'] as List).first as Map)['resource'] as Map;
      expect(set['total'], 1, reason: 'POSTs run before GETs');
    });
    test('a DELETE runs before a PUT of the same id', () async {
      final r = await send(
        'POST',
        '/',
        body: tx([
          {
            'resource': {
              'resourceType': 'Patient',
              'id': 'p1',
              'name': [
                {'family': 'Rewritten'},
              ],
            },
            'request': {'method': 'PUT', 'url': 'Patient/p1'},
          },
          {
            'request': {'method': 'DELETE', 'url': 'Patient/p1'},
          },
        ]),
      );
      await json(r, 200);
      final p1 = (await db.getResource(fhir.R4ResourceType.Patient, 'p1'))!
          as fhir.Patient;
      expect(p1.name?.first.family?.valueString, 'Rewritten');
    });
  });

  group('row 25: history paging links', () {
    test('a history page carries self, first, next and last', () async {
      for (var i = 0; i < 3; i++) {
        await send(
          'PUT',
          '/Patient/p1',
          body: {
            'resourceType': 'Patient',
            'id': 'p1',
            'name': [
              {'family': 'One$i'},
            ],
          },
        );
      }
      final b = await json(await send('GET', '/Patient/p1/_history?_count=2'));
      final rels = [
        for (final l in b['link'] as List) (l as Map)['relation'],
      ];
      expect(rels, containsAll(['self', 'first', 'next', 'last']));
      final next = ((b['link'] as List)
          .firstWhere((l) => (l as Map)['relation'] == 'next') as Map)['url'];
      expect(next, contains('_offset=2'));
      expect(next, contains('_count=2'));
      final page2 = await json(
        await send('GET', '/Patient/p1/_history?_count=2&_offset=2'),
      );
      expect((page2['entry'] as List).length, 2);
      final rels2 = [
        for (final l in page2['link'] as List) (l as Map)['relation'],
      ];
      expect(rels2, contains('previous'));
      expect(rels2, isNot(contains('next')));
    });
    test('type and system history page too', () async {
      for (final path in ['/Patient/_history?_count=1', '/_history?_count=1']) {
        final b = await json(await send('GET', path));
        final rels = [
          for (final l in b['link'] as List) (l as Map)['relation'],
        ];
        expect(rels, contains('next'), reason: path);
      }
    });
  });

  group('row 27: 404 bodies are OperationOutcomes', () {
    test(r'read, vread, history, PATCH, $meta', () async {
      for (final (method, path, headers) in [
        ('GET', '/Patient/nope', <String, String>{}),
        ('GET', '/Patient/nope/_history/1', <String, String>{}),
        ('GET', '/Patient/nope/_history', <String, String>{}),
        ('GET', r'/Patient/nope/$meta', <String, String>{}),
        (
          'PATCH',
          '/Patient/nope',
          {'content-type': 'application/json-patch+json'}
        ),
      ]) {
        final r = await handler(
          testRequest(
            method,
            path,
            authToken: token,
            body: method == 'PATCH' ? '[]' : null,
            headers: headers,
          ),
        );
        final text = await r.readAsString();
        expect(r.statusCode, 404, reason: '$method $path: $text');
        final body = jsonDecode(text) as Map<String, dynamic>;
        expect(body['resourceType'], 'OperationOutcome', reason: path);
        expect(
          ((body['issue'] as List).first as Map)['code'],
          'not-found',
          reason: path,
        );
      }
    });
  });

  group('row 28: SUBSETTED', () {
    test('is a meta.tag, not a security label', () async {
      final b = await json(await send('GET', '/Patient/p1?_summary=true'), 200);
      final meta = b['meta'] as Map<String, dynamic>;
      final tags = [for (final t in meta['tag'] as List) (t as Map)['code']];
      expect(tags, contains('SUBSETTED'));
      expect(meta['security'], isNull);
    });
  });

  group(r'row 29: $export refuses what it does not implement', () {
    test('patient, _elements, includeAssociatedData are 400', () async {
      for (final q in [
        'patient=Patient/p1',
        '_elements=Patient.name',
        'includeAssociatedData=LatestProvenanceResources',
      ]) {
        final r = await send(
          'GET',
          '/\$export?$q',
          headers: {'prefer': 'respond-async'},
        );
        final text = await r.readAsString();
        expect(r.statusCode, 400, reason: '$q: $text');
        expect(
          (jsonDecode(text) as Map)['resourceType'],
          'OperationOutcome',
        );
      }
    });
    test('and are ignored under Prefer: handling=lenient', () async {
      final r = await send(
        'GET',
        r'/$export?_elements=Patient.name',
        headers: {'prefer': 'respond-async, handling=lenient'},
      );
      expect(r.statusCode, 202, reason: await r.readAsString());
    });
  });
}
