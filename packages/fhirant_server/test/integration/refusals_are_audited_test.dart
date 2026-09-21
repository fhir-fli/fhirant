@Timeout(Duration(minutes: 2))
library;

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// A request the server turns away is still an attempt on the record, and
/// the trail must show it: who tried, and that it failed.
///
/// 45 CFR 164.308(a)(5)(ii)(C), verbatim: "Procedures for monitoring log-in
/// attempts and reporting discrepancies." 45 CFR 164.312(b), verbatim:
/// "Implement hardware, software, and/or procedural mechanisms that record
/// and examine activity in information systems that contain or use
/// electronic protected health information."
///
/// Measured 2026-09-21 before the fix: a garbled token, a deactivated
/// account and a valid token without the scope each answered 401 or 403
/// and left 0 audit records; only the allowed request left 1. The auth
/// check ran outside the audit step, so nothing it refused reached it.
///
/// A request with no credential at all stays unrecorded (ruled in
/// REVIEW_DECISIONS.md: it names nobody, and recording it gave any caller
/// an unbounded write).
void main() {
  late FhirAntDb db;
  late Handler handler;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
  });

  tearDown(() async => db.close());

  Future<List<fhir.AuditEvent>> events() async =>
      (await db.getResourcesByType(fhir.R4ResourceType.AuditEvent))
          .whereType<fhir.AuditEvent>()
          .toList();

  /// Sends GET /Patient with [token] and returns the events it added.
  Future<({int status, List<fhir.AuditEvent> added})> send(
    String? token,
  ) async {
    final before = (await events()).length;
    final response =
        await handler(testRequest('GET', '/Patient', authToken: token));
    // The queue writes on a 250 ms tick.
    var now = await events();
    for (var i = 0; i < 8 && now.length == before; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      now = await events();
    }
    return (status: response.statusCode, added: now.sublist(before));
  }

  String? idOf(fhir.AuditEvent e) =>
      e.agent.first.who?.identifier?.value?.valueString;
  String? nameOf(fhir.AuditEvent e) => e.agent.first.who?.display?.valueString;
  String? outcomeOf(fhir.AuditEvent e) => e.outcome?.valueString;

  test('no credential: refused, not recorded', () async {
    final r = await send(null);
    expect(r.status, 401);
    expect(r.added, isEmpty);
  });

  test('garbled token: refused and recorded as anonymous', () async {
    final r = await send('not.a.jwt');
    expect(r.status, 401);
    expect(r.added, hasLength(1));
    expect(outcomeOf(r.added.single), '4');
    expect(idOf(r.added.single), isNull);
    expect(nameOf(r.added.single), 'anonymous');
  });

  test('deactivated account: refused and recorded with its id', () async {
    final token =
        await issueTestToken(db, username: 'gone-user', scopes: ['user/*.rs']);
    final id = (await db.getUserByUsername('gone-user'))!.id;
    await db.customStatement('UPDATE users SET active = 0 WHERE id = $id');
    final r = await send(token);
    expect(r.status, 401);
    expect(r.added, hasLength(1));
    expect(outcomeOf(r.added.single), '4');
    expect(idOf(r.added.single), '$id');
    expect(nameOf(r.added.single), 'gone-user');
  });

  test('token older than an account change: refused and recorded', () async {
    final token =
        await issueTestToken(db, username: 'old-token', scopes: ['user/*.rs']);
    final id = (await db.getUserByUsername('old-token'))!.id;
    await db.customStatement(
      'UPDATE users SET token_generation = token_generation + 1 '
      'WHERE id = $id',
    );
    final r = await send(token);
    expect(r.status, 401);
    expect(r.added, hasLength(1));
    expect(outcomeOf(r.added.single), '4');
    expect(idOf(r.added.single), '$id');
  });

  test('valid user without the scope: refused and recorded', () async {
    final token = await issueTestToken(
      db,
      username: 'obs-only',
      scopes: ['user/Observation.rs'],
    );
    final id = (await db.getUserByUsername('obs-only'))!.id;
    final r = await send(token);
    expect(r.status, 403);
    expect(r.added, hasLength(1));
    expect(outcomeOf(r.added.single), '4');
    expect(idOf(r.added.single), '$id');
    expect(nameOf(r.added.single), 'obs-only');
  });

  test('allowed request: recorded as a success (control)', () async {
    final token =
        await issueTestToken(db, username: 'allowed', scopes: ['user/*.rs']);
    final id = (await db.getUserByUsername('allowed'))!.id;
    final r = await send(token);
    expect(r.status, 200);
    expect(r.added, hasLength(1));
    expect(outcomeOf(r.added.single), '0');
    expect(idOf(r.added.single), '$id');
  });

  test('dev mode: recorded under the dev-mode user (control)', () async {
    await db.close();
    final server = await createTestServer(devMode: true);
    db = server.db;
    handler = server.handler;
    final r = await send(null);
    expect(r.status, 200);
    expect(r.added, hasLength(1));
    expect(nameOf(r.added.single), 'dev-mode');
  });
}
