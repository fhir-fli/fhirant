import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-17 Q8. `_contained=true|both` was refused as "this server
/// does not index contained resources", while the store has indexed them
/// under `#Type` since fhir_db schema 7.
///
/// R4B search.html 3.1.1.5.5, read whole 2026-09-19: "By default, search
/// results only include resources that are not contained in other
/// resources"; `_contained` "true: return only contained resources", "both:
/// return both contained and non-contained (normal) resources";
/// `_containedType` "container (default): Return the container resources",
/// "contained: return only the contained resource", the latter with a
/// fullUrl like "http://example.com/fhir/MedicationRequest/23#m1"; and "the
/// server SHALL populate the entry.search.mode element".
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;
  late Directory exportDir;

  setUp(() async {
    exportDir = await Directory.systemTemp.createTemp('contained');
    final server = await createTestServer(exportDir: exportDir.path);
    db = server.db;
    handler = server.handler;
    token = await issueTestToken(
      db,
      username: 'admin',
      role: 'admin',
      scopes: ['system/*.*'],
    );
    // The page's own example: a MedicationRequest with a contained
    // Medication of a custom formulation.
    await db.saveResource(
      fhir.MedicationRequest.fromJson({
        'resourceType': 'MedicationRequest',
        'id': '23',
        'status': 'active',
        'intent': 'order',
        'contained': [
          {
            'resourceType': 'Medication',
            'id': 'm1',
            'code': {
              'coding': [
                {'system': 'http://acme.com/medications', 'code': 'abc'},
              ],
            },
          },
        ],
        'medicationReference': {'reference': '#m1'},
        'subject': {'reference': 'Patient/p1'},
      }),
    );
    // A stored, non-contained Medication with the same code.
    await db.saveResource(
      fhir.Medication.fromJson({
        'resourceType': 'Medication',
        'id': 'standalone',
        'code': {
          'coding': [
            {'system': 'http://acme.com/medications', 'code': 'abc'},
          ],
        },
      }),
    );
  });

  tearDown(() async {
    await db.close();
    await exportDir.delete(recursive: true);
  });

  Future<Map<String, dynamic>> search(String query, {int status = 200}) async {
    final r = await handler(
      testRequest(
        'GET',
        '/Medication?code=http://acme.com/medications|abc$query',
        authToken: token,
      ),
    );
    final text = await r.readAsString();
    expect(r.statusCode, status, reason: text);
    return jsonDecode(text) as Map<String, dynamic>;
  }

  List<Map<String, dynamic>> entriesOf(Map<String, dynamic> bundle) =>
      ((bundle['entry'] as List?) ?? const []).cast<Map<String, dynamic>>();

  test('by default the contained Medication is not a match', () async {
    final b = await search('');
    expect(b['total'], 1);
    expect(entriesOf(b).single['resource']['id'], 'standalone');
  });

  test('_contained=true returns the container, once, as a match', () async {
    final b = await search('&_contained=true');
    expect(b['total'], 1);
    final entry = entriesOf(b).single;
    expect(entry['resource']['resourceType'], 'MedicationRequest');
    expect(entry['resource']['id'], '23');
    expect(entry['search']['mode'], 'match');
    expect(entry['fullUrl'], endsWith('/MedicationRequest/23'));
  });

  test('_containedType=contained returns the contained resource itself',
      () async {
    final b = await search('&_contained=true&_containedType=contained');
    expect(b['total'], 1);
    final entry = entriesOf(b).single;
    expect(entry['resource']['resourceType'], 'Medication');
    expect(entry['resource']['id'], 'm1');
    expect(entry['fullUrl'], endsWith('/MedicationRequest/23#m1'));
    expect(entry['search']['mode'], 'match');
  });

  test('_contained=both returns the normal match and then the container',
      () async {
    final b = await search('&_contained=both');
    expect(b['total'], 2);
    expect(
      entriesOf(b).map((e) => e['resource']['id']).toList(),
      ['standalone', '23'],
    );
  });

  test('the page and its links are cut from the combined set', () async {
    final first = await search('&_contained=both&_count=1');
    expect(first['total'], 2);
    expect(entriesOf(first).single['resource']['id'], 'standalone');
    final links = {
      for (final l in first['link'] as List) l['relation']: l['url'],
    };
    expect(links, contains('next'));
    final second = await search('&_contained=both&_count=1&_offset=1');
    expect(entriesOf(second).single['resource']['id'], '23');
    final count = await search('&_contained=both&_summary=count');
    expect(count['total'], 2);
    expect(count['entry'], isNull);
  });

  test('what cannot be applied to the combined set is refused', () async {
    for (final extra in [
      '&_sort=_id',
      '&_include=Medication:manufacturer',
      '&_filter=${Uri.encodeQueryComponent('_id eq x')}',
    ]) {
      final outcome = await search('&_contained=true$extra', status: 400);
      expect(
        (outcome['issue'] as List).first['code'],
        'not-supported',
        reason: extra,
      );
    }
  });
}
