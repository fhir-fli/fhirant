import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// Type and system history pages are found from where the page before
/// ended, carried in the `next` link as `_cursor`, not counted from the
/// start with `_offset`: on the 1,868,395 versions of a synced MIMIC-IV
/// store a page at depth 1.87 million took 395 ms by offset and 1 ms by
/// position (measured 2026-11-20,
/// tool/sync_cost_2026-11-20/results_history_keyset.txt). R4B http.html
/// §3.1.0.14 (hl7.org/fhir/R4B/http.html, read 2026-11-20): "A server MAY
/// add additional state tracking parameters to the links"; "The client
/// must use the server supplied links in order to traverse the pages."
void main() {
  late FhirAntDb db;
  late Handler handler;

  setUp(() async {
    final server = await createTestServer(devMode: true);
    db = server.db;
    handler = server.handler;
    // One call, so most share a millisecond; and an update.
    await db.saveResources([
      for (var i = 0; i < 7; i++) fhir.Patient(id: 'p$i'.toFhirString),
      for (var i = 0; i < 3; i++) fhir.Organization(id: 'o$i'.toFhirString),
    ]);
    await db.saveResource(
      fhir.Patient(id: 'p2'.toFhirString, active: true.toFhirBoolean),
    );
  });

  tearDown(() => db.close());

  Future<Map<String, dynamic>> get(String url, {int status = 200}) async {
    final r = await handler(
      testRequest('GET', url, headers: {'accept': 'application/fhir+json'}),
    );
    final body = await r.readAsString();
    expect(r.statusCode, status, reason: body);
    return jsonDecode(body) as Map<String, dynamic>;
  }

  String? link(Map<String, dynamic> bundle, String relation) {
    for (final l in (bundle['link'] as List? ?? const [])) {
      if ((l as Map)['relation'] == relation) return l['url'] as String;
    }
    return null;
  }

  String key(Object? entry) {
    final e = entry! as Map;
    final r = e['resource'] as Map;
    return '${r['resourceType']}/${r['id']}/'
        '${(r['meta'] as Map)['versionId']}';
  }

  for (final (level, expected) in [
    ('/_history', 11),
    ('/Patient/_history', 8),
  ]) {
    test(
        '$level: following next links returns every version once, in the '
        'order one unpaged request gives', () async {
      final whole = await get(level);
      final all = (whole['entry'] as List).map(key).toList();
      expect(all, hasLength(expected));

      final paged = <String>[];
      var url = '$level?_count=3';
      var pages = 0;
      for (;;) {
        final page = await get(url);
        pages++;
        paged.addAll((page['entry'] as List? ?? const []).map(key));
        if (pages == 1) {
          expect(page['total'], expected);
        } else {
          // Counting every version again for each page is what a position
          // saves; the total is given once (http.html §3.1.0.14: "A server
          // MAY inform the client of the total").
          expect(page['total'], isNull);
        }
        final next = link(page, 'next');
        if (next == null) break;
        expect(Uri.parse(next).queryParameters, contains('_cursor'));
        expect(Uri.parse(next).queryParameters, isNot(contains('_offset')));
        final u = Uri.parse(next);
        url = '${u.path}?${u.query}';
      }
      expect(paged, all);
      expect(pages, (expected / 3).ceil());
    });
  }

  test('a cursor the server could not have given is refused', () async {
    for (final bad in [
      'x',
      '1|2|Patient',
      'nan|1|Patient|p1',
      '1|1|NotAType|p1',
      '1|1|Patient|bad id',
    ]) {
      final out = await get(
        '/_history?_cursor=${Uri.encodeQueryComponent(bad)}',
        status: 400,
      );
      expect(out['resourceType'], 'OperationOutcome', reason: bad);
    }
  });

  test('a cursor with _offset or _at is refused', () async {
    final first = await get('/_history?_count=2');
    final cursor = Uri.parse(link(first, 'next')!).queryParameters['_cursor']!;
    final c = Uri.encodeQueryComponent(cursor);
    await get('/_history?_cursor=$c&_offset=2', status: 400);
    await get('/_history?_cursor=$c&_at=2026-01-01T00:00:00Z', status: 400);
    await get('/_history?_cursor=$c&_cursor=$c', status: 400);
  });
}
