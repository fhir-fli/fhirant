import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-17 A13. For a patient token, another patient's
/// Observation was 403, an absent one 404, a deleted one 410: an existence
/// oracle over the whole store.
///
/// R4B security.html, "Access Denied Response Handling" (read 2026-09-19,
/// verbatim): "Return a 404 'Not Found' - This also protects from data
/// leakage as it is indistinguishable from a query against a resource that
/// doesn't exist." Every READ route answers a resource outside the
/// caller's compartment with the same bytes it answers an absent one.
/// Writes keep their 403: a PUT answered "not found" would mean create.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String p1Token;
  late Directory exportDir;

  setUp(() async {
    exportDir = await Directory.systemTemp.createTemp('outside');
    final server = await createTestServer(exportDir: exportDir.path);
    db = server.db;
    handler = server.handler;
    await db.saveResource(fhir.Patient(id: 'p1'.toFhirString));
    await db.saveResource(fhir.Patient(id: 'p2'.toFhirString));
    await db.saveResource(
      fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': 'o2',
        'status': 'final',
        'code': {'text': 'x'},
        'subject': {'reference': 'Patient/p2'},
      }),
    );
    await db.saveResource(
      fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': 'gone2',
        'status': 'final',
        'code': {'text': 'x'},
        'subject': {'reference': 'Patient/p2'},
      }),
    );
    await db.deleteResource(fhir.R4ResourceType.Observation, 'gone2');
    await db.saveResource(
      fhir.Composition.fromJson({
        'resourceType': 'Composition',
        'id': 'c2',
        'status': 'final',
        'type': {'text': 'note'},
        'date': '2026-01-01',
        'author': [
          {'reference': 'Patient/p2'},
        ],
        'title': 't',
        'subject': {'reference': 'Patient/p2'},
      }),
    );
    p1Token = await issueTestToken(
      db,
      username: 'patient-one',
      scopes: ['patient/*.cruds'],
      patientId: 'p1',
    );
  });

  tearDown(() async {
    await db.close();
    await exportDir.delete(recursive: true);
  });

  Future<(int, String)> send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    final r = await handler(
      testRequest(
        method,
        path,
        authToken: p1Token,
        headers: {
          if (body != null) 'content-type': 'application/fhir+json',
          ...?headers,
        },
        body: body == null ? null : jsonEncode(body),
      ),
    );
    return (r.statusCode, await r.readAsString());
  }

  test("a read of another patient's resource is byte-identical to absent",
      () async {
    // (route, the other patient's id, an absent id): the same answer, id
    // for id, since the body names the id the URL carried.
    const cases = {
      'read': ('/Observation/{id}', 'o2'),
      'deleted': ('/Observation/{id}', 'gone2'),
      'vread': ('/Observation/{id}/_history/1', 'o2'),
      'history': ('/Observation/{id}/_history', 'o2'),
      r'$meta': (r'/Observation/{id}/$meta', 'o2'),
      r'$document': (r'/Composition/{id}/$document', 'c2'),
      r'$everything': (r'/Patient/{id}/$everything', 'p2'),
      'compartment search': ('/Patient/{id}/Observation', 'p2'),
    };
    for (final entry in cases.entries) {
      final (route, otherId) = entry.value;
      final other = await send('GET', route.replaceAll('{id}', otherId));
      final absent = await send('GET', route.replaceAll('{id}', 'absent'));
      expect(absent.$1, 404, reason: '${entry.key}: the absent case');
      expect(other.$1, absent.$1, reason: entry.key);
      expect(
        other.$2,
        absent.$2.replaceAll('/absent', '/$otherId'),
        reason: entry.key,
      );
    }
  });

  test('a batch GET entry answers as absent too', () async {
    Future<Map<String, dynamic>> entry(String url) async {
      final (s, b) = await send(
        'POST',
        '/',
        body: {
          'resourceType': 'Bundle',
          'type': 'batch',
          'entry': [
            {
              'request': {'method': 'GET', 'url': url},
            },
          ],
        },
      );
      expect(s, 200, reason: b);
      final e = ((jsonDecode(b) as Map)['entry'] as List).single as Map;
      return (e['response'] as Map).cast<String, dynamic>();
    }

    final other = await entry('Observation/o2');
    final absent = await entry('Observation/absent');
    expect(absent['status'], '404');
    expect(other, absent);
  });

  test("a write on another patient's resource is still refused, not absent",
      () async {
    final obs = {
      'resourceType': 'Observation',
      'id': 'o2',
      'status': 'final',
      'code': {'text': 'x'},
      'subject': {'reference': 'Patient/p1'},
    };
    expect((await send('PUT', '/Observation/o2', body: obs)).$1, 403);
    expect((await send('DELETE', '/Observation/o2')).$1, 403);
    expect(
      (await send(
        'PATCH',
        '/Observation/o2',
        body: [
          {'op': 'replace', 'path': '/status', 'value': 'amended'},
        ],
        headers: {'content-type': 'application/json-patch+json'},
      ))
          .$1,
      403,
    );
    expect(
      (await send(
        'POST',
        r'/Observation/o2/$meta-add',
        body: {
          'resourceType': 'Parameters',
          'parameter': [
            {
              'name': 'meta',
              'valueMeta': {
                'tag': [
                  {'system': 'http://x', 'code': 'y'},
                ],
              },
            },
          ],
        },
      ))
          .$1,
      403,
    );
  });
}
