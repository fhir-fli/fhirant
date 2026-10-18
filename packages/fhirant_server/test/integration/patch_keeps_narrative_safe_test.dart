import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// R4B http.html 3.1.0.6, patch (hl7.org/fhir/R4B/http.html, read whole
/// 2026-10-17, verbatim): "The server SHALL ensure that the narrative in a
/// resource is not clinically unsafe after the PATCH operation is
/// performed", with, among the remedies it lists, "If the existing
/// narrative has a status != generated, the server could reject the PATCH
/// operation" and "The server could delete the narrative, on the basis that
/// some later process will be able to populate it correctly".
///
/// REVIEW-2026-10-17 finding 4, measured over HTTP: a potassium of 3.0 with
/// the narrative "Potassium 3.0 mmol/L (LOW)" patched to 6.5 read back with
/// the value 6.5 and the old narrative.
///
/// This server generates no narrative, so: a `generated` narrative (made
/// from the data, and so made again by whoever generates it) is removed; an
/// `additional` or `extensions` narrative (words a person wrote that the
/// data does not hold) refuses the patch, 422; an `empty` one is kept; a
/// patch that writes `/text` itself is the client keeping its narrative.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    token = await issueTestToken(db, scopes: ['user/*.*']);
  });

  tearDown(() => db.close());

  Future<void> store(String id, {String? status, String? div}) =>
      db.saveResource(
        fhir.Resource.fromJson({
          'resourceType': 'Observation',
          'id': id,
          'status': 'final',
          'code': {'text': 'Potassium'},
          'valueQuantity': {'value': 3.0, 'unit': 'mmol/L'},
          if (status != null)
            'text': {
              'status': status,
              'div': '<div xmlns="http://www.w3.org/1999/xhtml">'
                  '${div ?? 'Potassium 3.0 mmol/L (LOW)'}</div>',
            },
        }),
      );

  const toHigh = [
    {'op': 'replace', 'path': '/valueQuantity/value', 'value': 6.5},
  ];

  Future<Response> patch(String id, List<Object> ops) async => handler(
        testRequest(
          'PATCH',
          '/Observation/$id',
          body: jsonEncode(ops),
          headers: {'content-type': 'application/json-patch+json'},
          authToken: token,
        ),
      );

  Future<Map<String, dynamic>> read(String id) async =>
      (await db.getResource(fhir.R4ResourceType.Observation, id))!.toJson();

  test('an additional narrative refuses a patch of the data', () async {
    await store('a1', status: 'additional');
    final r = await patch('a1', toHigh);
    expect(r.statusCode, 422, reason: await r.readAsString());
    final stored = await read('a1');
    expect((stored['valueQuantity'] as Map)['value'], 3.0);
  });

  test('an extensions narrative refuses a patch of the data', () async {
    await store('e1', status: 'extensions');
    final r = await patch('e1', toHigh);
    expect(r.statusCode, 422);
  });

  test('a generated narrative is removed with the patch', () async {
    await store('g1', status: 'generated');
    final r = await patch('g1', toHigh);
    expect(r.statusCode, 200, reason: await r.readAsString());
    final stored = await read('g1');
    expect((stored['valueQuantity'] as Map)['value'], 6.5);
    expect(stored.containsKey('text'), isFalse);
  });

  test('an empty narrative is kept', () async {
    await store('m1', status: 'empty', div: 'No narrative');
    final r = await patch('m1', toHigh);
    expect(r.statusCode, 200);
    expect(((await read('m1'))['text'] as Map)['status'], 'empty');
  });

  test('a patch that writes the narrative too is accepted', () async {
    await store('a2', status: 'additional');
    final r = await patch('a2', [
      ...toHigh,
      {
        'op': 'replace',
        'path': '/text/div',
        'value': '<div xmlns="http://www.w3.org/1999/xhtml">Potassium 6.5 '
            'mmol/L (HIGH)</div>',
      },
    ]);
    expect(r.statusCode, 200, reason: await r.readAsString());
    final stored = await read('a2');
    expect((stored['text'] as Map)['div'], contains('6.5'));
  });

  test('a patch that changes only the narrative is accepted', () async {
    await store('a3', status: 'additional');
    final r = await patch('a3', [
      {'op': 'replace', 'path': '/text/status', 'value': 'generated'},
    ]);
    expect(r.statusCode, 200);
  });

  test('a resource with no narrative patches as before', () async {
    await store('n1');
    final r = await patch('n1', toHigh);
    expect(r.statusCode, 200);
  });

  test('a PATCH entry in a transaction follows the same rule', () async {
    await store('a4', status: 'additional');
    final r = await handler(
      testRequest(
        'POST',
        '/',
        body: jsonEncode({
          'resourceType': 'Bundle',
          'type': 'transaction',
          'entry': [
            {
              'resource': {
                'resourceType': 'Binary',
                'contentType': 'application/json-patch+json',
                'data': base64Encode(utf8.encode(jsonEncode(toHigh))),
              },
              'request': {'method': 'PATCH', 'url': 'Observation/a4'},
            },
          ],
        }),
        authToken: token,
      ),
    );
    expect(r.statusCode, 422, reason: await r.readAsString());
    expect(((await read('a4'))['valueQuantity'] as Map)['value'], 3.0);
  });
}
