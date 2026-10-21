import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// A username that is taken is the client's 409 "Username already exists",
/// however the requests arrive. Ten registrations of one name at once got
/// one 201 and nine 500s (concurrency_probe, 5 of 5; one at a time, 409s):
/// each passed the "is it taken" read, and the store's UNIQUE constraint
/// refused the INSERT, which the handler's catch-all answered as its own
/// failure. The constraint is the atomic check (OWASP ASVS 5.0.0 V15.4.2);
/// its refusal is now answered as the read's would be.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String admin;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    admin = await issueTestToken(
      db,
      username: 'adm',
      role: 'admin',
      scopes: ['system/*.*'],
    );
  });

  tearDown(() => db.close());

  test('ten registrations of one username at once: one 201, nine 409',
      () async {
    final rs = await Future.wait([
      for (var i = 0; i < 10; i++)
        Future.sync(
          () => handler(
            testRequest(
              'POST',
              '/auth/register',
              authToken: admin,
              body: jsonEncode({
                'username': 'dup',
                'password': 'a-long-enough-password-123',
              }),
            ),
          ),
        ),
    ]);
    final statuses = rs.map((r) => r.statusCode).toList()..sort();
    expect(statuses, [201, for (var i = 0; i < 9; i++) 409]);
    for (final r in rs.where((r) => r.statusCode == 409)) {
      expect(await r.readAsString(), contains('Username already exists'));
    }
  });
}
