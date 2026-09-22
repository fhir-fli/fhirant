import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// When the store cannot save, the cause reaches the log.
///
/// The store wrapper used to catch every failure of a save, print it to
/// stderr and return null; the handler then logged "Failed to save resource"
/// with the cause gone and answered "Database operation failed"
/// (REVIEW-2026-09-17 ST7). The one real instance was audit writes vanishing
/// with no line in the log (A16.10). Measured before this change: a save on
/// a closed store logged one SEVERE record whose `error` was null.
void main() {
  late FhirAntDb db;
  late Handler handler;

  setUp(() async {
    final server = await createTestServer(devMode: true);
    db = server.db;
    handler = server.handler;
  });

  test('a failed save logs its cause and the reply names it', () async {
    final severe = <LogRecord>[];
    final sub = Logger.root.onRecord
        .where((r) => r.level >= Level.SEVERE)
        .listen(severe.add);
    addTearDown(sub.cancel);

    // The failure: the store is closed under the running server. Dev mode,
    // so the auth check does not touch the store first.
    await db.close();

    final response = await handler(
      testRequest(
        'POST',
        '/Patient',
        headers: {'content-type': 'application/fhir+json'},
        body: '{"resourceType":"Patient"}',
      ),
    );
    final body = jsonDecode(await response.readAsString()) as Map;
    expect(response.statusCode, 500, reason: 'body: $body');
    expect(body['resourceType'], 'OperationOutcome');

    expect(severe, isNotEmpty, reason: 'nothing was logged at all');
    expect(
      severe.where((r) => r.error != null),
      isNotEmpty,
      reason: 'logged: ${severe.map((r) => r.message).toList()}; none '
          'carried the exception',
    );
  });
}
