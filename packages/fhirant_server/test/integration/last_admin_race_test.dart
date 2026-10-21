import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// The last active administrator cannot be demoted or deactivated (409;
/// account_handler). OWASP ASVS 5.0.0 V15.4.2 (read 2026-10-21): the check
/// and the action that depends on it "are performed as a single atomic
/// operation". The count of admins and the change were separate statements,
/// so two admins demoting each other at once both succeeded and the server
/// had none (concurrency_probe, 5 of 5; one at a time, one admin stayed).
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String a;
  late String b;
  late int idA;
  late int idB;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    a = await issueTestToken(
      db,
      username: 'adm-a',
      role: 'admin',
      scopes: ['system/*.*'],
    );
    b = await issueTestToken(
      db,
      username: 'adm-b',
      role: 'admin',
      scopes: ['system/*.*'],
    );
    idA = (await db.getUserByUsername('adm-a'))!.id;
    idB = (await db.getUserByUsername('adm-b'))!.id;
  });

  tearDown(() => db.close());

  Request demote(String token, int id) => testRequest(
        'PUT',
        '/admin/users/$id/role',
        authToken: token,
        body: jsonEncode({'role': 'clinician'}),
      );

  Request deactivate(String token, int id) =>
      testRequest('POST', '/admin/users/$id/deactivate', authToken: token);

  Future<List<String>> activeAdmins() async => [
        for (final n in ['adm-a', 'adm-b'])
          if (await db.getUserByUsername(n) case final u?
              when u.role == 'admin' && u.active)
            n,
      ];

  for (final (name, first, second) in [
    ('demote each other', demote, demote),
    ('deactivate each other', deactivate, deactivate),
    ('one demotes, the other deactivates', demote, deactivate),
  ]) {
    test('two admins $name at once: one admin is left', () async {
      final rs = await Future.wait([
        Future.sync(() => handler(first(a, idB))),
        Future.sync(() => handler(second(b, idA))),
      ]);
      final statuses = rs.map((r) => r.statusCode).toList()..sort();
      expect(statuses, [200, 409]);
      expect(await activeAdmins(), hasLength(1));
    });
  }
}
