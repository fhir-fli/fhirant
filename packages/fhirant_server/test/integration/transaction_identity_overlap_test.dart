import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// R4B http.html 3.1.0.11.2 (hl7.org/fhir/R4B/http.html, read whole
/// 2026-10-17, verbatim): "If any resource identities (including resolved
/// identities from conditional update/delete) overlap in steps 1-3, then
/// the transaction SHALL fail." Steps 1-3 are the DELETE, POST and PUT or
/// PATCH interactions. REVIEW-2026-10-17 finding 10: two PUTs of one id, or
/// a DELETE and a PUT of one id, in one transaction were accepted, and the
/// last processed won.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    token = await issueTestToken(db, scopes: ['user/*.*']);
    await db.saveResource(
      fhir.Resource.fromJson({
        'resourceType': 'Observation',
        'id': 'o1',
        'status': 'final',
        'code': {'text': 'stored'},
      }),
    );
  });

  tearDown(() => db.close());

  Map<String, dynamic> obs(String id, String text) => {
        'resourceType': 'Observation',
        'id': id,
        'status': 'final',
        'code': {'text': text},
      };

  Map<String, dynamic> put(String id, String text) => {
        'resource': obs(id, text),
        'request': {'method': 'PUT', 'url': 'Observation/$id'},
      };

  Future<Response> transaction(List<Map<String, dynamic>> entries) async =>
      handler(
        testRequest(
          'POST',
          '/',
          body: jsonEncode({
            'resourceType': 'Bundle',
            'type': 'transaction',
            'entry': entries,
          }),
          authToken: token,
        ),
      );

  Future<String?> storedText() async =>
      ((await db.getResource(fhir.R4ResourceType.Observation, 'o1'))
              as fhir.Observation?)
          ?.code
          .text
          ?.valueString;

  test('two PUTs of one id fail the transaction', () async {
    final r = await transaction([put('o1', 'first'), put('o1', 'second')]);
    expect(r.statusCode, 400, reason: await r.readAsString());
    expect(await storedText(), 'stored');
  });

  test('a DELETE and a PUT of one id fail the transaction', () async {
    final r = await transaction([
      {
        'request': {'method': 'DELETE', 'url': 'Observation/o1'},
      },
      put('o1', 'again'),
    ]);
    expect(r.statusCode, 400, reason: await r.readAsString());
    expect(await storedText(), 'stored');
  });

  test('a PUT and a PATCH of one id fail the transaction', () async {
    final r = await transaction([
      put('o1', 'first'),
      {
        'resource': {
          'resourceType': 'Binary',
          'contentType': 'application/json-patch+json',
          'data': base64Encode(
            utf8.encode(
              jsonEncode([
                {'op': 'replace', 'path': '/status', 'value': 'amended'},
              ]),
            ),
          ),
        },
        'request': {'method': 'PATCH', 'url': 'Observation/o1'},
      },
    ]);
    expect(r.statusCode, 400, reason: await r.readAsString());
  });

  test('a conditional update that resolves to an id already written fails',
      () async {
    final r = await transaction([
      put('o1', 'first'),
      {
        'resource': {
          'resourceType': 'Observation',
          'status': 'final',
          'code': {'text': 'second'},
        },
        'request': {'method': 'PUT', 'url': 'Observation?_id=o1'},
      },
    ]);
    expect(r.statusCode, 400, reason: await r.readAsString());
  });

  test('controls: different ids, and a GET beside a PUT of one id', () async {
    final r = await transaction([put('o1', 'one'), put('o2', 'two')]);
    expect(r.statusCode, 200, reason: await r.readAsString());
    final g = await transaction([
      put('o1', 'three'),
      {
        'request': {'method': 'GET', 'url': 'Observation/o1'},
      },
    ]);
    expect(g.statusCode, 200, reason: await g.readAsString());
  });
}
