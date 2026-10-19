import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// R4B http.html 3.1.0.11.2 (hl7.org/fhir/R4B/http.html, read 2026-10-18):
/// "For a transaction, servers SHALL either accept all actions and return a
/// 200 OK, along with a response bundle ... It is not an error if the
/// submitted bundle has no resources in it." 3.1.0.11.1: "the HTTP response
/// code is 200 Ok if the batch was processed correctly". REVIEW-2026-10-17
/// (smaller list): a Bundle with no entries was 400 "Bundle must contain at
/// least one entry".
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    token = await issueTestToken(db);
  });

  tearDown(() => db.close());

  Future<(int, Map<String, dynamic>)> post(Map<String, dynamic> bundle) async {
    final r = await handler(
      testRequest(
        'POST',
        '/',
        body: jsonEncode(bundle),
        headers: {'content-type': 'application/fhir+json'},
        authToken: token,
      ),
    );
    return (
      r.statusCode,
      jsonDecode(await r.readAsString()) as Map<String, dynamic>,
    );
  }

  for (final (type, responseType) in [
    ('transaction', 'transaction-response'),
    ('batch', 'batch-response'),
  ]) {
    test('a $type with no entry element is 200 $responseType', () async {
      final (status, body) =
          await post({'resourceType': 'Bundle', 'type': type});
      expect(status, 200, reason: '$body');
      expect(body['resourceType'], 'Bundle');
      expect(body['type'], responseType);
      // R4B json.html (read 2026-10-18): "JSON objects and arrays are never
      // empty"; no entries, no element.
      expect(body.containsKey('entry'), isFalse, reason: '$body');
    });

    test('a $type with an empty entry list is 200 $responseType', () async {
      final (status, body) = await post(
        {'resourceType': 'Bundle', 'type': type, 'entry': <Object>[]},
      );
      expect(status, 200, reason: '$body');
      expect(body['type'], responseType);
      expect(body.containsKey('entry'), isFalse, reason: '$body');
    });
  }

  test('control: a Bundle of another type is still refused', () async {
    final (status, body) =
        await post({'resourceType': 'Bundle', 'type': 'collection'});
    expect(status, 400);
    expect(body['resourceType'], 'OperationOutcome');
  });
}
