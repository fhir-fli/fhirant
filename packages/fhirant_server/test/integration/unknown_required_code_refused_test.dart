import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/unknown_codes.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// R4B http.html 3.1.0.8 (hl7.org/fhir/R4B/http.html, read whole
/// 2026-10-17, verbatim): "When the resource syntax or data is incorrect or
/// invalid, and cannot be used to create a new resource, the server returns
/// a 400 Bad Request HTTP status code." REVIEW-2026-10-17 finding 8:
/// `Observation.status: "not-a-status"` (a required binding) was stored
/// 201, read back and searched. The check flags none of the 3,012 parseable
/// published R4B examples (tool/review_2026-10-17/unknown_codes_census.tsv).
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
        'code': {'text': 'x'},
      }),
    );
  });

  tearDown(() => db.close());

  Map<String, dynamic> obs(String status, {String? id}) => {
        'resourceType': 'Observation',
        if (id != null) 'id': id,
        'status': status,
        'code': {'text': 'x'},
      };

  Future<Response> send(
    String method,
    String path,
    Object body, {
    String contentType = 'application/fhir+json',
  }) async =>
      handler(
        testRequest(
          method,
          path,
          body: jsonEncode(body),
          headers: {'content-type': contentType},
          authToken: token,
        ),
      );

  Future<String?> storedStatus() async =>
      ((await db.getResource(fhir.R4ResourceType.Observation, 'o1'))!
              as fhir.Observation)
          .status
          .valueString;

  test('the check finds a top-level and a nested unknown code', () {
    expect(
      unknownRequiredCodes(fhir.Resource.fromJson(obs('not-a-status'))),
      ['Observation.status = not-a-status'],
    );
    expect(
      unknownRequiredCodes(
        fhir.Resource.fromJson({
          'resourceType': 'Patient',
          'identifier': [
            {'use': 'official', 'value': 'a'},
            {'use': 'nope', 'value': 'b'},
          ],
        }),
      ),
      ['Patient.identifier[1].use = nope'],
    );
    expect(unknownRequiredCodes(fhir.Resource.fromJson(obs('final'))), isEmpty);
  });

  test('create', () async {
    final r = await send('POST', '/Observation', obs('not-a-status'));
    expect(r.statusCode, 400, reason: await r.readAsString());
    final ok = await send('POST', '/Observation', obs('final'));
    expect(ok.statusCode, 201);
  });

  test('update', () async {
    final r =
        await send('PUT', '/Observation/o1', obs('not-a-status', id: 'o1'));
    expect(r.statusCode, 400, reason: await r.readAsString());
    expect(await storedStatus(), 'final');
  });

  test('patch', () async {
    final r = await send(
      'PATCH',
      '/Observation/o1',
      [
        {'op': 'replace', 'path': '/status', 'value': 'not-a-status'},
      ],
      contentType: 'application/json-patch+json',
    );
    expect(r.statusCode, 400, reason: await r.readAsString());
    expect(await storedStatus(), 'final');
  });

  test('a transaction entry fails the transaction', () async {
    final r = await send('POST', '/', {
      'resourceType': 'Bundle',
      'type': 'transaction',
      'entry': [
        {
          'resource': obs('not-a-status'),
          'request': {'method': 'POST', 'url': 'Observation'},
        },
      ],
    });
    expect(r.statusCode, 400, reason: await r.readAsString());
  });

  test('a batch entry fails alone', () async {
    final r = await send('POST', '/', {
      'resourceType': 'Bundle',
      'type': 'batch',
      'entry': [
        {
          'resource': obs('not-a-status'),
          'request': {'method': 'POST', 'url': 'Observation'},
        },
        {
          'resource': obs('final'),
          'request': {'method': 'POST', 'url': 'Observation'},
        },
      ],
    });
    final entries = (jsonDecode(await r.readAsString())
        as Map<String, dynamic>)['entry'] as List;
    expect(
      [for (final e in entries) ((e as Map)['response'] as Map)['status']],
      [startsWith('400'), startsWith('201')],
    );
  });
}
