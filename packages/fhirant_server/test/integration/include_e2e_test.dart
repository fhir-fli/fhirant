import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/resource_handler.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// `_include` and `_revinclude` against a real database.
///
/// R4B search.html 3.1.1.5.4, read whole 2026-09-06: "Both _include and
/// _revinclude are based on search parameters, rather than paths in the
/// resource". Two defects hid behind the mocked tests: `_include` walked the
/// JSON for a key named like the parameter, so `Observation:patient` (element
/// `subject`) found nothing; and `_revinclude` passed one list element per
/// match, an AND since fhir_r4_db 0.11.0, so a page with two matches got no
/// includes at all.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    token = generateTestToken(scopes: ['user/*.cruds']);
    for (final id in ['p1', 'p2']) {
      await db.saveResource(
        fhir.Patient.fromJson({
          'resourceType': 'Patient',
          'id': id,
          'name': [
            {'family': 'Inc'},
          ],
        }),
      );
    }
    await db.saveResource(
      fhir.Practitioner.fromJson({'resourceType': 'Practitioner', 'id': 'dr1'}),
    );
    for (final (id, subject) in [('o1', 'p1'), ('o2', 'p2'), ('o3', 'p2')]) {
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
          'subject': {'reference': 'Patient/$subject'},
          'performer': [
            {'reference': 'Practitioner/dr1'},
          ],
        }),
      );
    }
    // A reference to a Patient that does not exist here.
    await db.saveResource(
      fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': 'o-dangling',
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '8867-4'},
          ],
        },
        'subject': {'reference': 'Patient/nobody'},
      }),
    );
    await db.saveResource(
      fhir.Provenance.fromJson({
        'resourceType': 'Provenance',
        'id': 'prov1',
        'target': [
          {'reference': 'Patient/p1'},
          {'reference': 'Patient/p2'},
        ],
        'recorded': '2024-01-01T00:00:00Z',
        'agent': [
          {
            'who': {'reference': 'Practitioner/dr1'},
          },
        ],
      }),
    );
  });
  tearDown(() async => db.close());

  Future<Map<String, dynamic>> get(String path) async {
    final response = await handler(testRequest('GET', path, authToken: token));
    expect(response.statusCode, 200, reason: path);
    return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
  }

  List<String> entriesOf(Map<String, dynamic> b, String mode) =>
      ((b['entry'] as List?) ?? [])
          .where((e) => (e as Map)['search']['mode'] == mode)
          .map((e) => '${e['resource']['resourceType']}/${e['resource']['id']}')
          .toList()
        ..sort();

  test('_include follows the search parameter, not the element name', () async {
    // `patient` is defined on Observation.subject.where(resolve() is Patient).
    final b = await get('/Observation?_id=o1&_include=Observation:patient');
    expect(entriesOf(b, 'match'), ['Observation/o1']);
    expect(entriesOf(b, 'include'), ['Patient/p1']);
  });

  test('_include with a target type keeps only that type', () async {
    final all = await get('/Observation?_id=o1&_include=Observation:*');
    expect(entriesOf(all, 'include'), ['Patient/p1', 'Practitioner/dr1']);
    final only = await get(
      '/Observation?_id=o1&_include=Observation:performer:Practitioner',
    );
    expect(entriesOf(only, 'include'), ['Practitioner/dr1']);
    final none = await get(
      '/Observation?_id=o1&_include=Observation:performer:Organization',
    );
    expect(entriesOf(none, 'include'), isEmpty);
  });

  test('a spec whose source type is not the matched type adds nothing',
      () async {
    final b = await get('/Observation?_id=o1&_include=Patient:link');
    expect(entriesOf(b, 'include'), isEmpty);
  });

  test('a dangling reference is omitted, and no error is returned', () async {
    final b = await get(
      '/Observation?_id=o-dangling&_include=Observation:subject',
    );
    expect(entriesOf(b, 'match'), ['Observation/o-dangling']);
    expect(entriesOf(b, 'include'), isEmpty);
  });

  test('_revinclude over a page with several matches includes for all of them',
      () async {
    // Two Patients match; the referencing Observations of BOTH come back.
    final b = await get('/Patient?family=Inc&_revinclude=Observation:subject');
    expect(entriesOf(b, 'match'), ['Patient/p1', 'Patient/p2']);
    expect(
      entriesOf(b, 'include'),
      ['Observation/o1', 'Observation/o2', 'Observation/o3'],
    );
  });

  test('_revinclude with a target type', () async {
    final b =
        await get('/Patient?family=Inc&_revinclude=Provenance:target:Patient');
    expect(entriesOf(b, 'include'), ['Provenance/prov1']);
    final none = await get(
      '/Patient?family=Inc&_revinclude=Provenance:target:Organization',
    );
    expect(entriesOf(none, 'include'), isEmpty);
  });

  group('the page carries at most maxIncluded included resources (finding 39)',
      () {
    late int previous;
    setUp(() => previous = maxIncluded);
    tearDown(() => maxIncluded = previous);

    test('_revinclude past the bound: the first ones, and an outcome entry',
        () async {
      maxIncluded = 2;
      final b =
          await get('/Patient?family=Inc&_revinclude=Observation:subject');
      expect(entriesOf(b, 'match'), ['Patient/p1', 'Patient/p2']);
      expect(entriesOf(b, 'include'), hasLength(2));
      final outcomes = (b['entry'] as List)
          .cast<Map<String, dynamic>>()
          .where((e) => e['search']?['mode'] == 'outcome')
          .toList();
      expect(outcomes, hasLength(1));
      final issue = (outcomes.single['resource']['issue'] as List).single
          as Map<String, dynamic>;
      expect(issue['code'], 'too-costly');
      expect(issue['severity'], 'warning');
      expect(issue['diagnostics'], contains('first 2 included'));
    });

    test('_include past the bound: the first ones, and an outcome entry',
        () async {
      maxIncluded = 1;
      final b = await get('/Observation?_include=Observation:subject');
      expect(entriesOf(b, 'include'), hasLength(1));
      expect(
        (b['entry'] as List)
            .cast<Map<String, dynamic>>()
            .where((e) => e['search']?['mode'] == 'outcome'),
        hasLength(1),
      );
    });

    test('within the bound there is no outcome entry', () async {
      final b =
          await get('/Patient?family=Inc&_revinclude=Observation:subject');
      expect(
        (b['entry'] as List)
            .cast<Map<String, dynamic>>()
            .where((e) => e['search']?['mode'] == 'outcome'),
        isEmpty,
      );
    });
  });

  test('each page carries its own includes (3.1.1.5.7)', () async {
    final first = await get(
      '/Patient?family=Inc&_count=1&_revinclude=Observation:subject',
    );
    final second = await get(
      '/Patient?family=Inc&_count=1&_offset=1&_revinclude=Observation:subject',
    );
    final firstMatch = entriesOf(first, 'match').single;
    final secondMatch = entriesOf(second, 'match').single;
    expect(firstMatch, isNot(secondMatch));
    // Each page's includes point at that page's match only.
    for (final (page, match) in [(first, firstMatch), (second, secondMatch)]) {
      final includes = entriesOf(page, 'include');
      expect(includes, isNotEmpty);
      final patientId = match.split('/').last;
      final expected = patientId == 'p1'
          ? ['Observation/o1']
          : ['Observation/o2', 'Observation/o3'];
      expect(includes, expected);
    }
  });

  test('_include:iterate follows on from the included resources', () async {
    final b = await get(
      '/Provenance?_id=prov1&_include=Provenance:target'
      '&_include:iterate=Patient:general-practitioner',
    );
    // Nothing further: neither Patient has a general practitioner. The point
    // is the source type of the iterate spec is matched against the INCLUDED
    // resources, not the matches.
    expect(entriesOf(b, 'include'), ['Patient/p1', 'Patient/p2']);
  });
}
