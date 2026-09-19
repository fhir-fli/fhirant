// Real Argon2id hashes on the logins.
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-17 A16: a refused login left no AuditEvent at all (a 401
/// with no Authorization header was skipped as a bare refusal), so the
/// trail could not show whose account was being tried. Now it is recorded
/// with the claimed name in `agent.name` and `agent.who.display`, and no
/// identifier: nothing was proven about who typed it.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late Directory exportDir;
  const password = 'Audit-Password-1';

  setUp(() async {
    exportDir = await Directory.systemTemp.createTemp('failedlogin');
    final server = await createTestServer(exportDir: exportDir.path);
    db = server.db;
    handler = server.handler;
    final salt = PasswordHasher.generateSalt();
    await db.createUser(
      username: 'audited-user',
      passwordHash: await PasswordHasher.hashPassword(password, salt),
      salt: salt,
    );
  });

  tearDown(() async {
    await db.close();
    await exportDir.delete(recursive: true);
  });

  Future<int> login(String user, String pass) async => (await handler(
        testRequest(
          'POST',
          '/auth/login',
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'username': user, 'password': pass}),
        ),
      ))
          .statusCode;

  /// The trail, once the queue's tick has written it.
  Future<List<fhir.AuditEvent>> trail() async {
    var events = <fhir.AuditEvent>[];
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      events = (await db.search(resourceType: fhir.R4ResourceType.AuditEvent))
          .cast<fhir.AuditEvent>();
      if (events.isNotEmpty) break;
    }
    return events;
  }

  test('a wrong password is recorded with the name that was tried', () async {
    expect(await login('audited-user', 'not-the-password'), 401);
    final events = await trail();
    expect(events, hasLength(1));
    final agent = events.single.agent.single;
    expect(agent.name?.valueString, 'audited-user');
    expect(agent.who?.display?.valueString, 'audited-user');
    expect(agent.who?.identifier, isNull, reason: 'nothing proven');
    expect(events.single.outcome?.valueString, '4');
  });

  test('an unknown account is recorded with the name that was tried', () async {
    expect(await login('nobody-here', 'not-the-password'), 401);
    final events = await trail();
    expect(events, hasLength(1));
    expect(events.single.agent.single.name?.valueString, 'nobody-here');
  });

  test('a bare unauthenticated read is still not recorded', () async {
    final r = await handler(testRequest('GET', '/Patient'));
    expect(r.statusCode, 401);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final events =
        await db.search(resourceType: fhir.R4ResourceType.AuditEvent);
    expect(events, isEmpty);
  });
}
