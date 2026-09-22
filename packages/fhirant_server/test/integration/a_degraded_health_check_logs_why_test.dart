import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// When the health check reports the store degraded, the log says why.
///
/// `/health` caught every failure of its store probe and answered
/// "degraded" with nothing written anywhere (one of eight catches that
/// swallowed the cause, REVIEW-2026-09-17 audit of 2026-09-22). Measured
/// before the change: a closed store gave `degraded` and no log record.
void main() {
  test('a closed store is reported degraded, with the cause logged', () async {
    final server = await createTestServer(devMode: true);
    final records = <LogRecord>[];
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);

    await server.db.close();
    final response = await server.handler(testRequest('GET', '/health'));
    final body = jsonDecode(await response.readAsString()) as Map;
    expect(body['status'], 'degraded');
    expect(
      records.where((r) => r.level >= Level.WARNING && r.error != null),
      isNotEmpty,
      reason: 'logged: ${records.map((r) => r.message).toList()}',
    );
  });
}
