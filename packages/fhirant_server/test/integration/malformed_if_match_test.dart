import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/http_headers.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// R4B http.html 3.1.0.5 (hl7.org/fhir/R4B/http.html, read whole
/// 2026-10-17, verbatim): "If the version id given in the If-Match header
/// does not match, the server returns a 412 Precondition Failed status code
/// instead of updating the resource." A header that names no version
/// matches none. REVIEW-2026-10-17 finding 9: `If-Match: garbage` and
/// `If-Match: W/1` were read as no header at all, and the update ran
/// unconditionally (200), so a client with a bad header lost the protection
/// against overwriting another's change without knowing.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    token = await issueTestToken(db, scopes: ['user/*.*']);
    for (var i = 0; i < 2; i++) {
      await db.saveResource(
        fhir.Resource.fromJson({
          'resourceType': 'Observation',
          'id': 'o1',
          'status': 'final',
          'code': {'text': 'v$i'},
        }),
      );
    }
  });

  tearDown(() => db.close());

  final body = {
    'resourceType': 'Observation',
    'id': 'o1',
    'status': 'amended',
    'code': {'text': 'mine'},
  };

  Future<Response> send(
    String method,
    String ifMatch, {
    Object? json,
    String contentType = 'application/fhir+json',
  }) async =>
      handler(
        testRequest(
          method,
          '/Observation/o1',
          body: json == null ? null : jsonEncode(json),
          headers: {'if-match': ifMatch, 'content-type': contentType},
          authToken: token,
        ),
      );

  test('parseETag', () {
    expect(FhirHttpHeaders.parseETag(null), isNull);
    expect(FhirHttpHeaders.parseETag(''), isNull);
    expect(FhirHttpHeaders.parseETag('*'), isNull);
    expect(FhirHttpHeaders.parseETag('W/"2"'), '2');
    expect(FhirHttpHeaders.parseETag('"2"'), '2');
    for (final bad in ['garbage', 'W/2', '2', 'W/"2', '"2" junk']) {
      final parsed = FhirHttpHeaders.parseETag(bad);
      expect(parsed, isNotNull, reason: bad);
      expect(
        RegExp(r'^[A-Za-z0-9\-.]{1,64}$').hasMatch(parsed!),
        isFalse,
        reason: '$bad must not parse to something a version id could be',
      );
    }
  });

  for (final bad in ['garbage', 'W/2']) {
    test('PUT with If-Match: $bad is 412', () async {
      final r = await send('PUT', bad, json: body);
      expect(r.statusCode, 412, reason: await r.readAsString());
    });

    test('PATCH with If-Match: $bad is 412', () async {
      final r = await send(
        'PATCH',
        bad,
        json: [
          {'op': 'replace', 'path': '/status', 'value': 'amended'},
        ],
        contentType: 'application/json-patch+json',
      );
      expect(r.statusCode, 412, reason: await r.readAsString());
    });

    test('DELETE with If-Match: $bad is 412', () async {
      final r = await send('DELETE', bad);
      expect(r.statusCode, 412, reason: await r.readAsString());
      expect(
        await db.getResource(fhir.R4ResourceType.Observation, 'o1'),
        isNotNull,
      );
    });

    test('a transaction PUT with ifMatch $bad fails', () async {
      final r = await handler(
        testRequest(
          'POST',
          '/',
          body: jsonEncode({
            'resourceType': 'Bundle',
            'type': 'transaction',
            'entry': [
              {
                'resource': body,
                'request': {
                  'method': 'PUT',
                  'url': 'Observation/o1',
                  'ifMatch': bad,
                },
              },
            ],
          }),
          authToken: token,
        ),
      );
      expect(r.statusCode, 412, reason: await r.readAsString());
    });
  }

  test('the current version still matches', () async {
    final r = await send('PUT', 'W/"2"', json: body);
    expect(r.statusCode, 200, reason: await r.readAsString());
  });

  test('If-Match: * still updates an existing resource', () async {
    final r = await send('PUT', '*', json: body);
    expect(r.statusCode, 200);
  });
}
