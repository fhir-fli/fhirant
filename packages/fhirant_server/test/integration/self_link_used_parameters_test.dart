import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// R4B search.html 3.1.1.6 (hl7.org/fhir/R4B/search.html, read 2026-10-18,
/// verbatim): "In order to allow the client to be confident about what
/// search parameters were used as criteria by the server, the server SHALL
/// return the parameters that were actually used to process the search. ...
/// In the case of a RESTful search, these parameters are encoded in the self
/// link in the bundle that is returned". 3.1.1.5.4: the second part of an
/// `_include`/`_revinclude` is "The name of the search parameter which must
/// be of type reference". REVIEW-2026-10-17 (smaller list):
/// `_include=Observation:not-a-param` stayed in the self link. Found while
/// fixing: a parameter uploaded as a SearchParameter is searched by, and was
/// left out of the self link.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    token = await issueTestToken(
      db,
      username: 'self-admin',
      role: 'admin',
      scopes: ['system/*.*'],
    );
    for (final r in <Map<String, dynamic>>[
      {'resourceType': 'Patient', 'id': 'p1'},
      {
        'resourceType': 'Observation',
        'id': 'o1',
        'status': 'final',
        'code': {'text': 'x'},
        'subject': {'reference': 'Patient/p1'},
      },
      {
        'resourceType': 'Provenance',
        'id': 'prov1',
        'target': [
          {'reference': 'Patient/p1'},
        ],
        'recorded': '2026-10-18T00:00:00Z',
        'agent': [
          {
            'who': {'display': 'clerk'},
          },
        ],
      },
    ]) {
      await db.saveResource(fhir.Resource.fromJson(r));
    }
  });

  tearDown(() => db.close());

  Future<Map<String, dynamic>> search(
    String query, {
    Map<String, String> headers = const {},
  }) async {
    final r = await handler(
      testRequest('GET', '/$query', authToken: token, headers: headers),
    );
    final text = await r.readAsString();
    expect(r.statusCode, 200, reason: text);
    return jsonDecode(text) as Map<String, dynamic>;
  }

  /// The self link's query, every repetition.
  Map<String, List<String>> self(Map<String, dynamic> bundle) {
    final link = (bundle['link'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((l) => l['relation'] == 'self');
    return Uri.parse(link['url'] as String).queryParametersAll;
  }

  List<String> types(Map<String, dynamic> bundle) => [
        for (final e in (bundle['entry'] as List?) ?? const [])
          if ((e as Map)['resource'] as Map case final r)
            '${r['resourceType']}/${r['id']}',
      ]..sort();

  test('an _include on an unknown parameter is not in the self link', () async {
    final b = await search('Observation?_include=Observation:not-a-param');
    expect(self(b).containsKey('_include'), isFalse, reason: '${self(b)}');
    expect(types(b), ['Observation/o1']);
  });

  test('an _include on a parameter that is not a reference is not either',
      () async {
    final b = await search('Observation?_include=Observation:status');
    expect(self(b).containsKey('_include'), isFalse, reason: '${self(b)}');
  });

  test('of two _includes, only the one used is in the self link', () async {
    final b = await search(
      'Observation?_include=Observation:subject'
      '&_include=Observation:not-a-param',
    );
    expect(self(b)['_include'], ['Observation:subject']);
    expect(types(b), ['Observation/o1', 'Patient/p1']);
  });

  test('control: _include with * and with a target type stay', () async {
    final b = await search(
      'Observation?_include=Observation:*'
      '&_include=Observation:subject:Patient',
    );
    expect(
      self(b)['_include'],
      ['Observation:*', 'Observation:subject:Patient'],
    );
  });

  test(
      'a _revinclude on an unknown parameter is not in the self link, '
      'and adds nothing', () async {
    final b = await search('Patient?_revinclude=Provenance:not-a-param');
    expect(self(b).containsKey('_revinclude'), isFalse, reason: '${self(b)}');
    expect(types(b), ['Patient/p1']);
  });

  test('control: a _revinclude on a real parameter stays and adds', () async {
    final b = await search('Patient?_revinclude=Provenance:target');
    expect(self(b)['_revinclude'], ['Provenance:target']);
    expect(types(b), ['Patient/p1', 'Provenance/prov1']);
  });

  test('Prefer: handling=strict refuses an unknown _include', () async {
    final r = await handler(
      testRequest(
        'GET',
        '/Observation?_include=Observation:not-a-param',
        authToken: token,
        headers: {'prefer': 'handling=strict'},
      ),
    );
    expect(r.statusCode, 400, reason: await r.readAsString());
  });

  group('an uploaded SearchParameter', () {
    setUp(() async {
      final r = await handler(
        testRequest(
          'PUT',
          '/SearchParameter/obs-performer-ref',
          authToken: token,
          headers: {'content-type': 'application/fhir+json'},
          body: jsonEncode({
            'resourceType': 'SearchParameter',
            'id': 'obs-performer-ref',
            'url': 'http://example.org/fhir/SearchParameter/obs-focus-ref',
            'name': 'ObsFocusRef',
            'status': 'active',
            'description': 'Observation.focus, as an uploaded parameter.',
            'code': 'focus-ref',
            'base': ['Observation'],
            'type': 'reference',
            'expression': 'Observation.focus',
          }),
        ),
      );
      expect(r.statusCode, 201, reason: await r.readAsString());
      await db.saveResource(
        fhir.Resource.fromJson({
          'resourceType': 'Observation',
          'id': 'o2',
          'status': 'final',
          'code': {'text': 'y'},
          'focus': [
            {'reference': 'Patient/p1'},
          ],
        }),
      );
    });

    test('a search by it is in the self link', () async {
      final b = await search('Observation?focus-ref=Patient/p1');
      expect(types(b), ['Observation/o2']);
      expect(self(b)['focus-ref'], ['Patient/p1'], reason: '${self(b)}');
    });

    test('an _include by it is in the self link and adds', () async {
      final b = await search(
        'Observation?_id=o2&_include=Observation:focus-ref',
      );
      expect(types(b), ['Observation/o2', 'Patient/p1']);
      expect(self(b)['_include'], ['Observation:focus-ref']);
    });

    test('handling=strict accepts a search by it', () async {
      final b = await search(
        'Observation?focus-ref=Patient/p1',
        headers: {'prefer': 'handling=strict'},
      );
      expect(types(b), ['Observation/o2']);
    });
  });
}
