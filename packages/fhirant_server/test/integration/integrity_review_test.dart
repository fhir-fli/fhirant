import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// The integrity findings of REVIEW-2026-09-06.md that reach the HTTP
/// surface: If-Match checked inside the write (finding 30), the saved
/// resource returned rather than re-read (32), and the history of a deleted
/// resource readable, with the delete as a DELETE entry in instance, type
/// and system history (25, and the tombstone parse the DAO fix found).
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

  Map<String, dynamic> observation(String id, {String status = 'final'}) => {
        'resourceType': 'Observation',
        'id': id,
        'status': status,
        'code': {'text': 'x'},
      };

  Future<Response> put(
    Map<String, dynamic> resource, {
    String? ifMatch,
  }) async =>
      handler(
        testRequest(
          'PUT',
          '/${resource['resourceType']}/${resource['id']}',
          body: jsonEncode(resource),
          headers: {
            'content-type': 'application/fhir+json',
            if (ifMatch != null) 'if-match': ifMatch,
          },
        ),
      );

  group('If-Match on update and delete (finding 30)', () {
    test('a stale If-Match is 412 and writes nothing', () async {
      await json(await put(observation('o1')), 201);
      final v2 = await json(await put(observation('o1')), 200);
      expect(v2['meta']['versionId'], '2');

      final stale = await put(observation('o1'), ifMatch: 'W/"1"');
      final body = await json(stale, 412);
      expect(body['resourceType'], 'OperationOutcome');
      expect(
        (await db.getResource(fhir.R4ResourceType.Observation, 'o1'))!
            .meta!
            .versionId!
            .valueString,
        '2',
      );

      final current = await json(
        await put(observation('o1'), ifMatch: 'W/"2"'),
        200,
      );
      expect(current['meta']['versionId'], '3');
    });

    test('If-Match on a resource that does not exist is 412', () async {
      final r = await put(observation('never'), ifMatch: 'W/"1"');
      await json(r, 412);
      expect(
        await db.getResource(fhir.R4ResourceType.Observation, 'never'),
        isNull,
      );
    });

    test('DELETE with a stale If-Match is 412; with the current one, 204',
        () async {
      await json(await put(observation('o2')), 201);
      await json(await put(observation('o2')), 200);
      final stale = await handler(
        testRequest(
          'DELETE',
          '/Observation/o2',
          headers: {'if-match': 'W/"1"'},
        ),
      );
      await json(stale, 412);
      expect(
        await db.getResource(fhir.R4ResourceType.Observation, 'o2'),
        isNotNull,
      );
      final ok = await handler(
        testRequest(
          'DELETE',
          '/Observation/o2',
          headers: {'if-match': 'W/"2"'},
        ),
      );
      expect(ok.statusCode, 204);
      expect(
        await db.getResource(fhir.R4ResourceType.Observation, 'o2'),
        isNull,
      );
    });
  });

  group('a deleted Observation (finding 25 and the tombstone parse)', () {
    setUp(() async {
      await json(await put(observation('gone')), 201);
      await json(await put(observation('gone', status: 'amended')), 200);
      final r = await handler(testRequest('DELETE', '/Observation/gone'));
      expect(r.statusCode, 204);
    });

    test('GET is 410, not an error', () async {
      final r = await handler(testRequest('GET', '/Observation/gone'));
      final body = await json(r, 410);
      expect(body['issue'][0]['code'], 'deleted');
    });

    test('instance history has the delete as a DELETE entry with no resource',
        () async {
      final bundle = await json(
        await handler(testRequest('GET', '/Observation/gone/_history')),
        200,
      );
      final entries = (bundle['entry'] as List).cast<Map<String, dynamic>>();
      expect(entries, hasLength(3));
      expect(entries[0]['request']['method'], 'DELETE');
      expect(entries[0]['request']['url'], 'Observation/gone');
      expect(entries[0]['response']['status'], '204');
      expect(entries[0].containsKey('resource'), isFalse);
      expect(entries[1]['request']['method'], 'PUT');
      expect(entries[1]['resource']['status'], 'amended');
      expect(entries[2]['request']['method'], 'POST');
      expect(entries[2]['request']['url'], 'Observation');
      expect(entries[2]['resource']['meta']['versionId'], '1');
    });

    test('type and system history carry the same DELETE entry', () async {
      for (final path in ['/Observation/_history', '/_history']) {
        final bundle = await json(await handler(testRequest('GET', path)), 200);
        final entries = (bundle['entry'] as List).cast<Map<String, dynamic>>();
        final deletes =
            entries.where((e) => e['request']['method'] == 'DELETE').toList();
        expect(deletes, hasLength(1), reason: path);
        expect(deletes.single['request']['url'], 'Observation/gone');
        expect(deletes.single.containsKey('resource'), isFalse);
        expect(
          entries.every(
            (e) => e['request']['method'] == 'DELETE' || e['resource'] != null,
          ),
          isTrue,
          reason: 'every non-delete entry carries its resource',
        );
      }
    });

    test('vread of the tombstone version is 410; of an earlier one, 200',
        () async {
      await json(
        await handler(testRequest('GET', '/Observation/gone/_history/3')),
        410,
      );
      final v1 = await json(
        await handler(testRequest('GET', '/Observation/gone/_history/1')),
        200,
      );
      expect(v1['status'], 'final');
    });
  });

  test('the created resource in the response is the stored one (finding 32)',
      () async {
    final created = await json(
      await handler(
        testRequest(
          'POST',
          '/Observation',
          body: jsonEncode(observation('any')..remove('id')),
          headers: {'content-type': 'application/fhir+json'},
        ),
      ),
      201,
    );
    final stored = await db.getResource(
      fhir.R4ResourceType.Observation,
      created['id'] as String,
    );
    expect(created['meta'], stored!.meta!.toJson());
  });
}
