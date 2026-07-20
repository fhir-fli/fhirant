import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// Rate limiting must key on the real TCP connection, not the client-supplied
/// X-Forwarded-For header — otherwise an attacker rotates the header to get a
/// fresh bucket per request and defeats brute-force/DoS protection.
void main() {
  test('a rotating X-Forwarded-For does not create fresh rate-limit buckets',
      () async {
    final db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();

    const maxRequests = 5;
    final server = FhirAntServer(
      db,
      jwtSecret: 'test-secret',
      maxRequests: maxRequests,
      devMode: true,
    );
    // Port 0 → the OS assigns an ephemeral port.
    await server.startHttp(0);
    addTearDown(() async {
      await server.stop();
      await db.close();
    });

    final base = 'http://127.0.0.1:${server.port}';
    final statuses = <int>[];
    // Every request carries a DIFFERENT spoofed X-Forwarded-For. If the limiter
    // trusted the header, each would be its own bucket and none would be 429.
    for (var i = 0; i < maxRequests + 3; i++) {
      final response = await http.get(
        Uri.parse('$base/health'),
        headers: {'X-Forwarded-For': '10.0.0.$i'},
      );
      statuses.add(response.statusCode);
    }

    // Because all requests share the real (localhost) connection, the bucket is
    // exhausted after maxRequests and later requests are rejected (429).
    expect(
      statuses.where((s) => s == 429),
      isNotEmpty,
      reason: 'spoofed X-Forwarded-For should not bypass the rate limit; '
          'got statuses $statuses',
    );
  });
}
