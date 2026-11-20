import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// A version saved after the server's clock is set back is still returned
/// to a reader following `_history?_since` (R4B http.html §3.1.0.12, read
/// 2026-11-19: "Only include resource versions that were created at or
/// after the given instant in time"): fhir_db 0.15.3 stamps a version no
/// earlier than the last one the store gave. Before it, the version was
/// stamped by the clock, before the reader's cursor, and never returned.
void main() {
  late ({FhirAntDb db, Handler handler, FhirAntServer server}) here;

  setUp(() async {
    here = await createTestServer(devMode: true);
  });

  tearDown(() async {
    await here.server.stop();
    await here.db.close();
  });

  Future<Response> send(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async =>
      here.handler(
        testRequest(
          method,
          path,
          headers: {'content-type': 'application/fhir+json'},
          body: body == null ? null : jsonEncode(body),
        ),
      );

  test(
      '_since keeps a version saved at the instant it names, at every '
      'level', () async {
    // "created at or after the given instant": the type and system
    // history read `last_updated > ?` until 2026-11-19, and fhir_db's
    // instance history too.
    final saved = await send('PUT', '/Patient/q', {
      'resourceType': 'Patient',
      'id': 'q',
    });
    final at = (jsonDecode(await saved.readAsString())
        as Map<String, dynamic>)['meta']['lastUpdated'] as String;
    for (final path in [
      '/_history',
      '/Patient/_history',
      '/Patient/q/_history',
    ]) {
      final reply = await send(
        'GET',
        '$path?_since=${Uri.encodeQueryComponent(at)}',
      );
      final bundle =
          jsonDecode(await reply.readAsString()) as Map<String, dynamic>;
      expect(bundle['total'], 1, reason: '$path: $bundle');
    }
  });

  test('a save after the clock is set back reaches a _since reader', () async {
    await send('PUT', '/Patient/p', {'resourceType': 'Patient', 'id': 'p'});
    // The state a clock running a day ahead leaves: the store's last
    // stamp, and the version a reader last saw, a day from now.
    final ahead = DateTime.now().toUtc().add(const Duration(days: 1));
    await here.db.customStatement(
      'CREATE TABLE IF NOT EXISTS store_clock '
      '(id INTEGER PRIMARY KEY CHECK (id = 0), last_stamp INTEGER NOT NULL)',
    );
    await here.db.customStatement(
      'INSERT OR REPLACE INTO store_clock (id, last_stamp) '
      'VALUES (0, ${ahead.microsecondsSinceEpoch})',
    );
    final cursor = ahead.toIso8601String();

    // The clock is right again, and someone saves.
    final saved = await send('PUT', '/Patient/p', {
      'resourceType': 'Patient',
      'id': 'p',
      'gender': 'male',
    });
    expect(saved.statusCode, 200);

    final reply = await send(
      'GET',
      '/_history?_since=${Uri.encodeQueryComponent(cursor)}',
    );
    final bundle =
        jsonDecode(await reply.readAsString()) as Map<String, dynamic>;
    final genders = [
      for (final e in (bundle['entry'] as List? ?? const []))
        ((e as Map)['resource'] as Map?)?['gender'],
    ];
    expect(genders, contains('male'), reason: '$bundle');
  });
}
