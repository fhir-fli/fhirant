// Real Argon2id hashes when a token is minted, and a wait per route for
// the audit queue's 250 ms tick.
@Timeout(Duration(minutes: 6))
library;

import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// Every route the server registers is called with a credential that
/// covers it, and the audit trail must gain a record.
///
/// The route list is read from `createRouter`'s own registrations, for the
/// reason `every_route_is_guarded_test.dart` gives: a hand-written list
/// can only hold the routes someone remembered, which is how the three
/// authorization gaps in REVIEW-2026-09-17 survived.
///
/// ISO 27789:2021 is what the trail is for: an audit record identifies the
/// user, the subject of care and the action. A route that leaves no record
/// is a use of the record that nobody can review afterwards.
void main() {
  List<({String verb, String path})> registeredRoutes() {
    final source = File('lib/src/fhirant_server.dart').readAsStringSync();
    final pattern = RegExp(
      r"\.\.(get|post|put|delete|patch|all|head|mount|add)\(\s*r?'([^']+)'",
      dotAll: true,
    );
    return [
      for (final m in pattern.allMatches(source))
        (verb: m.group(1)!.toUpperCase(), path: m.group(2)!),
    ];
  }

  /// Routes the middleware skips on purpose, with the reason.
  const notAudited = <String, String>{
    '/': 'the welcome page reads no record',
    '/favicon.ico': 'an icon',
    '/health': 'a poll that reads no record; it used to write an event per '
        'poll (REVIEW-2026-09-08 row 45)',
    '/metadata': 'the capability statement reads no record',
    '/.well-known/smart-configuration': 'discovery, reads no record',
    '/ws': 'a websocket upgrade, not a request with a response',
  };

  /// The id the admin routes act on: a second account, never the caller's.
  /// With `<userId>` mapped to 1 this loop deactivated its own admin at
  /// route 5, every later request was refused by the auth middleware (which
  /// runs before the audit middleware, so a refusal leaves no record), and
  /// the count froze: 60 routes looked unaudited. That was the whole cause.
  late int targetUserId;

  String concrete(String path) => path
      .replaceAll('<resourceType>', 'Patient')
      .replaceAll('<compartmentType>', 'Patient')
      .replaceAll('<compartmentId>', 'p1')
      .replaceAll('<groupId>', 'g1')
      .replaceAll('<userId>', '$targetUserId')
      .replaceAll('<jobId>', 'j1')
      .replaceAll('<fileName>', 'f.ndjson')
      .replaceAll('<vid>', '1')
      .replaceAll('<id>', 'p1');

  late FhirAntDb db;
  late Handler handler;
  late Directory exportDir;
  late String adminToken;

  setUp(() async {
    exportDir = await Directory.systemTemp.createTemp('audited');
    final server = await createTestServer(exportDir: exportDir.path);
    db = server.db;
    handler = server.handler;
    adminToken = await issueTestToken(
      db,
      username: 'audit-admin',
      role: 'admin',
      scopes: ['system/*.*'],
    );
    await db.saveResource(fhir.Patient(id: 'p1'.toFhirString));
    targetUserId = await createTargetUser(db);
  });

  tearDown(() async {
    await db.close();
    await exportDir.delete(recursive: true);
  });

  /// COUNT(*) straight off the table, so the number does not depend on any
  /// search behaviour. (An earlier version of this comment blamed paging
  /// for a frozen count; that was wrong: `search()` with no `count` returns
  /// every row, measured 2026-09-21 at 45 of 45. The count froze because
  /// the loop deactivated its own account; see [targetUserId].)
  Future<int> auditCount() async => (await db
          .customSelect(
            'SELECT count(*) AS n FROM resources WHERE resource_type = '
            "'AuditEvent'",
          )
          .getSingle())
      .read<int>('n');

  test('every route that touches the record leaves an audit event', () async {
    final unaudited = <String>[];
    final audited = <String>[];
    for (final route in registeredRoutes()) {
      if (notAudited.containsKey(route.path)) continue;
      // `auth/` routes answer credentials, not the record; a refused login
      // is audited (A16.9) and a successful one by the same path, so they
      // are exercised by their own tests rather than here.
      if (route.path.startsWith('/auth/')) continue;
      final verb = route.verb == 'ALL' ? 'GET' : route.verb;
      final before = await auditCount();
      await handler(
        testRequest(verb, concrete(route.path), authToken: adminToken),
      );
      // The queue writes on a 250 ms tick.
      var after = before;
      for (var i = 0; i < 8 && after == before; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        after = await auditCount();
      }
      final line = '$verb ${route.path}';
      (after > before ? audited : unaudited).add(line);
    }
    expect(
      unaudited,
      isEmpty,
      reason: 'these routes left no record of the request',
    );
    expect(audited.length, greaterThan(60));
  });
}
