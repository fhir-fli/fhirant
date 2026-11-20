import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// R4B http.html §3.1.0.11.4 (read 2026-11-19): "servers SHOULD accept a
/// history Bundle - this makes it possible to replicate data from one
/// server to another easily using a pub/sub model". A resource may occur
/// more than once; every version is applied, oldest first, all or nothing,
/// and a POST entry keeps `resource.id`, which "must match the
/// Bundle.entry.response.location".
void main() {
  late ({FhirAntDb db, Handler handler, FhirAntServer server}) from;
  late ({FhirAntDb db, Handler handler, FhirAntServer server}) to;

  setUp(() async {
    from = await createTestServer(devMode: true);
    to = await createTestServer(devMode: true);
  });

  tearDown(() async {
    await from.server.stop();
    await to.server.stop();
    await from.db.close();
    await to.db.close();
  });

  Future<Response> send(
    Handler handler,
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async =>
      handler(
        testRequest(
          method,
          path,
          headers: {'content-type': 'application/fhir+json'},
          body: body == null ? null : jsonEncode(body),
        ),
      );

  Future<Map<String, dynamic>> json(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, dynamic>;

  Future<Response> postHistory(List<Map<String, dynamic>> entries) =>
      send(to.handler, 'POST', '/', {
        'resourceType': 'Bundle',
        'type': 'history',
        'entry': entries,
      });

  test("another server's history replays here, every version in order",
      () async {
    // Created by POST (so the history says POST), changed twice; a second
    // resource created and deleted.
    final created = await json(
      await send(from.handler, 'POST', '/Patient', {
        'resourceType': 'Patient',
        'gender': 'female',
      }),
    );
    final id = created['id'] as String;
    for (final gender in ['male', 'other']) {
      final r = await send(from.handler, 'PUT', '/Patient/$id', {
        'resourceType': 'Patient',
        'id': id,
        'gender': gender,
      });
      expect(r.statusCode, 200);
    }
    await send(from.handler, 'PUT', '/Patient/gone', {
      'resourceType': 'Patient',
      'id': 'gone',
    });
    await send(from.handler, 'DELETE', '/Patient/gone');

    final history = await json(await send(from.handler, 'GET', '/_history'));
    final entries = (history['entry'] as List).cast<Map<String, dynamic>>();
    expect(entries, hasLength(5));

    final reply = await postHistory(entries);
    final body = await json(reply);
    expect(reply.statusCode, 200, reason: '$body');
    expect(body['type'], 'transaction-response');
    expect(body['entry'], hasLength(5));

    // The current version is the newest, under the same id.
    final current = await json(await send(to.handler, 'GET', '/Patient/$id'));
    expect(current['gender'], 'other');
    // Every version arrived, in the order they were saved.
    final versions =
        await to.db.getResourceHistory(fhir.R4ResourceType.Patient, id);
    expect(
      versions.reversed.map((v) => v.toJson()['gender']),
      ['female', 'male', 'other'],
    );
    // And the delete.
    expect((await send(to.handler, 'GET', '/Patient/gone')).statusCode, 410);
  });

  test('one entry that fails leaves nothing applied', () async {
    final reply = await postHistory([
      {
        'resource': {'resourceType': 'Patient', 'id': 'b', 'gender': 'bogus'},
        'request': {'method': 'PUT', 'url': 'Patient/b'},
      },
      {
        'resource': {'resourceType': 'Patient', 'id': 'a'},
        'request': {'method': 'POST', 'url': 'Patient'},
      },
    ]);
    expect(reply.statusCode, greaterThanOrEqualTo(400));
    expect(
      await to.db.getResource(fhir.R4ResourceType.Patient, 'a'),
      isNull,
    );
  });

  test(
      'a POST entry whose response.location names another resource is '
      'refused', () async {
    final reply = await postHistory([
      {
        'resource': {'resourceType': 'Patient', 'id': 'a'},
        'request': {'method': 'POST', 'url': 'Patient'},
        'response': {'status': '201', 'location': 'Patient/b/_history/1'},
      },
    ]);
    expect(reply.statusCode, 400);
    expect(
      await to.db.getResource(fhir.R4ResourceType.Patient, 'a'),
      isNull,
    );
  });

  test(
      'an entry with no request, no resource id, or a DELETE of no id is '
      'refused', () async {
    for (final entry in [
      {
        'resource': {'resourceType': 'Patient', 'id': 'a'},
      },
      {
        'resource': {'resourceType': 'Patient'},
        'request': {'method': 'POST', 'url': 'Patient'},
      },
      {
        'request': {'method': 'DELETE', 'url': 'Patient'},
      },
    ]) {
      final reply = await postHistory([entry]);
      expect(reply.statusCode, 400, reason: '$entry');
      // Refused by the history rules, with the reason, not by whatever the
      // entry would have broken further on.
      expect(
        await reply.readAsString(),
        anyOf(contains('history Bundle'), contains('missing request')),
        reason: '$entry',
      );
    }
  });

  test('a history create entry carries the Location its create answered',
      () async {
    await send(from.handler, 'PUT', '/Patient/x', {
      'resourceType': 'Patient',
      'id': 'x',
    });
    final history = await json(
      await send(from.handler, 'GET', '/Patient/x/_history'),
    );
    final entry = (history['entry'] as List).single as Map<String, dynamic>;
    expect(entry['response']['location'], 'Patient/x/_history/1');
  });
}
