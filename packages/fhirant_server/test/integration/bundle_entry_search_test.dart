import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-17 Q6. A type-level GET entry of a batch or transaction
/// Bundle ran a second search of its own that knew `searchParams`,
/// `_count`, `_offset` and `_sort` and nothing else: `_has`, `_include`,
/// `_revinclude`, `_summary`, `_elements`, `_filter` and `_total` were
/// dropped, so a REST search and the same search as an entry disagreed
/// (the review: REST total 1, entry total 2). Both now run `typeSearch`.
///
/// Each URL below is sent both ways and the two searchset Bundles must
/// agree on `total`, on the ids and search modes of their entries, and on
/// the shape of each resource.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;
  late Directory exportDir;

  setUp(() async {
    exportDir = await Directory.systemTemp.createTemp('entry-search');
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
        gender: fhir.AdministrativeGender.female,
        name: [fhir.HumanName(family: 'One'.toFhirString)],
      ),
    );
    await db.saveResource(
      fhir.Patient(
        id: 'p2'.toFhirString,
        gender: fhir.AdministrativeGender.female,
        name: [fhir.HumanName(family: 'Two'.toFhirString)],
      ),
    );
    await db.saveResource(
      fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': 'obs1',
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '1234-5'},
          ],
        },
        'subject': {'reference': 'Patient/p1'},
      }),
    );
  });

  tearDown(() async {
    await db.close();
    await exportDir.delete(recursive: true);
  });

  Future<Map<String, dynamic>> rest(
    String url, {
    Map<String, String>? headers,
  }) async {
    final r = await handler(
      testRequest('GET', '/$url', authToken: token, headers: headers),
    );
    final text = await r.readAsString();
    expect(r.statusCode, 200, reason: 'REST $url: $text');
    return jsonDecode(text) as Map<String, dynamic>;
  }

  Future<Response> batch(
    List<String> urls, {
    Map<String, String>? headers,
  }) async =>
      handler(
        testRequest(
          'POST',
          '/',
          authToken: token,
          headers: {'content-type': 'application/fhir+json', ...?headers},
          body: jsonEncode({
            'resourceType': 'Bundle',
            'type': 'batch',
            'entry': [
              for (final url in urls)
                {
                  'request': {'method': 'GET', 'url': url},
                },
            ],
          }),
        ),
      );

  /// The searchset each batch entry carries, in order.
  Future<List<Map<String, dynamic>>> entrySets(
    List<String> urls, {
    Map<String, String>? headers,
  }) async {
    final r = await batch(urls, headers: headers);
    final text = await r.readAsString();
    expect(r.statusCode, 200, reason: text);
    final entries = (jsonDecode(text) as Map<String, dynamic>)['entry'] as List;
    return [
      for (final e in entries)
        () {
          final entry = e as Map<String, dynamic>;
          expect(
            (entry['response'] as Map)['status'],
            '200',
            reason: jsonEncode(entry),
          );
          return entry['resource'] as Map<String, dynamic>;
        }(),
    ];
  }

  /// What a searchset says: total, and (id, search mode, sorted keys of the
  /// resource) per entry.
  Object summary(Map<String, dynamic> set) {
    expect(set['type'], 'searchset');
    return {
      'total': set['total'],
      'entries': [
        for (final e in (set['entry'] as List?) ?? const [])
          {
            'id': (e as Map)['resource']['id'],
            'mode': (e['search'] as Map?)?['mode'],
            'keys': ((e['resource'] as Map).keys.toList()..sort()).join(','),
          },
      ],
    };
  }

  const urls = [
    // _has: only the patient with the observation.
    'Patient?_has:Observation:patient:code=http://loinc.org|1234-5',
    // _include: the observation and its patient.
    'Observation?_include=Observation:patient',
    // _revinclude: the patient and the observation that points at it.
    'Patient?_id=p1&_revinclude=Observation:patient',
    // _summary=count: a total and no entries.
    'Patient?_summary=count',
    // _elements: only id (and the mandatory elements) come back.
    'Patient?_elements=id',
    // _filter: evaluated, not ignored (`sw`; this server refuses `eq` on a
    // string, on both paths).
    'Patient?_filter=family%20sw%20%22On%22',
    // _total=none: no total.
    'Patient?_total=none',
    // The plain case still agrees.
    'Patient?gender=female',
  ];

  test('a batch entry search answers exactly what the REST search answers',
      () async {
    final sets = await entrySets(urls);
    for (var i = 0; i < urls.length; i++) {
      expect(
        summary(sets[i]),
        summary(await rest(urls[i])),
        reason: urls[i],
      );
    }
  });

  test('the answers are the ones the parameters ask for', () async {
    final sets = await entrySets(urls);
    // _has
    expect(sets[0]['total'], 1);
    expect((sets[0]['entry'] as List).single['resource']['id'], 'p1');
    // _include
    expect(
      (sets[1]['entry'] as List).map((e) => (e as Map)['search']['mode']),
      ['match', 'include'],
    );
    // _revinclude
    expect(
      (sets[2]['entry'] as List).map((e) => (e as Map)['resource']['id']),
      ['p1', 'obs1'],
    );
    // _summary=count
    expect(sets[3]['total'], 2);
    expect(sets[3]['entry'], isNull);
    // _elements
    for (final e in sets[4]['entry'] as List) {
      expect((e as Map)['resource'], isNot(contains('name')));
    }
    // _filter
    expect(sets[5]['total'], 1);
    // _total=none
    expect(sets[6], isNot(contains('total')));
  });

  test('Prefer: handling=strict reaches the entry', () async {
    final headers = {'prefer': 'handling=strict'};
    final r = await batch(['Patient?nonsense=1'], headers: headers);
    final text = await r.readAsString();
    expect(r.statusCode, 200, reason: text);
    final entry = ((jsonDecode(text) as Map<String, dynamic>)['entry'] as List)
        .single as Map<String, dynamic>;
    expect((entry['response'] as Map)['status'], '400', reason: text);
    // And the same URL on its own is a 400 too.
    final rest400 = await handler(
      testRequest(
        'GET',
        '/Patient?nonsense=1',
        authToken: token,
        headers: headers,
      ),
    );
    expect(rest400.statusCode, 400);
  });
}
