import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/search_parser.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-06 §5 at the HTTP surface: `_count` bounded (finding 22),
/// `$everything` paged before it hydrates, with links (35), conditional
/// delete bounded and transactional (41).
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

  Map<String, dynamic> observation(String id, String patient) => {
        'resourceType': 'Observation',
        'id': id,
        'status': 'final',
        'code': {'text': 'x'},
        'subject': {'reference': 'Patient/$patient'},
      };

  group('_count (finding 22)', () {
    test('a negative _count is refused', () async {
      final body = await json(
        await handler(testRequest('GET', '/Observation?_count=-1')),
        400,
      );
      expect(body['issue'][0]['code'], 'invalid');
    });

    test(
        'a page never exceeds the server maximum, and the self link keeps '
        'the _count the client sent', () async {
      await db.saveResources([
        for (var i = 0; i < kMaxPageSize + 5; i++)
          fhir.Observation.fromJson(observation('o$i', 'p')),
      ]);
      final body = await json(
        await handler(testRequest('GET', '/Observation?_count=100000')),
        200,
      );
      expect(body['total'], kMaxPageSize + 5);
      expect(body['entry'], hasLength(kMaxPageSize));
      final self = (body['link'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((l) => l['relation'] == 'self')['url'] as String;
      expect(self, contains('_count=100000'));
    });

    test('_count=0 is the count-only form', () async {
      await db.saveResource(fhir.Observation.fromJson(observation('o1', 'p')));
      final body = await json(
        await handler(testRequest('GET', '/Observation?_count=0')),
        200,
      );
      expect(body['total'], 1);
      expect(body['entry'], isNull);
    });
  });

  // `_type` names the two types, because dev-mode auditing writes
  // AuditEvents into the Patient compartment between the calls.
  group(r'$everything pages its ids (finding 35)', () {
    setUp(() async {
      await db.saveResource(
        fhir.Patient.fromJson({'resourceType': 'Patient', 'id': 'pe'}),
      );
      for (var i = 0; i < 3; i++) {
        await db
            .saveResource(fhir.Observation.fromJson(observation('e$i', 'pe')));
      }
    });

    test('a page and its links', () async {
      final first = await json(
        await handler(
          testRequest(
            'GET',
            r'/Patient/pe/$everything?_type=Patient,Observation&_count=2',
          ),
        ),
        200,
      );
      expect(first['total'], 4);
      final entries = (first['entry'] as List).cast<Map<String, dynamic>>();
      expect(entries, hasLength(2));
      expect(entries[0]['resource']['resourceType'], 'Patient');
      final links = {
        for (final l in (first['link'] as List).cast<Map<String, dynamic>>())
          l['relation'] as String: l['url'] as String,
      };
      expect(links['self'], contains('_offset=0'));
      expect(links['next'], contains('_offset=2'));
      // Every other parameter rides along on the paging links.
      expect(links['next'], contains('_type=Patient%2CObservation'));
      expect(links['next'], contains('_count=2'));
      expect(links.containsKey('previous'), isFalse);

      final second = await json(
        await handler(
          testRequest(
            'GET',
            r'/Patient/pe/$everything?_type=Patient,Observation&_count=2&_offset=2',
          ),
        ),
        200,
      );
      final more = (second['entry'] as List).cast<Map<String, dynamic>>();
      expect(more, hasLength(2));
      expect(
        more.every((e) => e['resource']['resourceType'] == 'Observation'),
        isTrue,
      );
      final links2 = {
        for (final l in (second['link'] as List).cast<Map<String, dynamic>>())
          l['relation'] as String: l['url'] as String,
      };
      expect(links2.containsKey('next'), isFalse);
      expect(links2['previous'], contains('_offset=0'));
      final all = {
        ...entries.map((e) => e['resource']['id']),
        ...more.map((e) => e['resource']['id']),
      };
      expect(all, {'pe', 'e0', 'e1', 'e2'});
    });

    test('past the end: an empty page with the total', () async {
      final body = await json(
        await handler(
          testRequest(
            'GET',
            r'/Patient/pe/$everything?_type=Patient,Observation&_count=2&_offset=10',
          ),
        ),
        200,
      );
      expect(body['total'], 4);
      expect(body['entry'], isNull);
    });
  });

  group('conditional delete (finding 41)', () {
    test('within the bound, every match goes', () async {
      for (var i = 0; i < 3; i++) {
        await db
            .saveResource(fhir.Observation.fromJson(observation('d$i', 'pd')));
      }
      final r = await handler(
        testRequest('DELETE', '/Observation?subject=Patient/pd'),
      );
      expect(r.statusCode, 204);
      expect(
        await db.searchCount(
          resourceType: fhir.R4ResourceType.Observation,
          searchParameters: {
            'subject': ['Patient/pd'],
          },
        ),
        0,
      );
    });

    test('above the bound, 412 and nothing deleted', () async {
      await db.saveResources([
        for (var i = 0; i < kMaxConditionalDeletes + 1; i++)
          fhir.Observation.fromJson(observation('m$i', 'pm')),
      ]);
      final r = await handler(
        testRequest('DELETE', '/Observation?subject=Patient/pm'),
      );
      final body = await json(r, 412);
      expect(body['issue'][0]['code'], 'too-costly');
      expect(
        await db.searchCount(
          resourceType: fhir.R4ResourceType.Observation,
          searchParameters: {
            'subject': ['Patient/pm'],
          },
        ),
        kMaxConditionalDeletes + 1,
      );
    });
  });
}
