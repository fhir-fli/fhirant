import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// Verifies that privileged root-level system operations ($backup/$restore/
/// $export…) are gated to system-level (admin) callers through the full
/// middleware pipeline — not reachable by ordinary authenticated users.
void main() {
  group('System operation authorization', () {
    late dynamic handler;
    late FhirAntDb db;

    setUp(() async {
      final server = await createTestServer();
      handler = server.handler;
      db = server.db;
    });

    // A representative destructive/full-DB operation from each category.
    // The export status and file routes are not here: they are answered to
    // the job's owner and to system authority (REVIEW-2026-09-08 row 12),
    // and tested below.
    final privilegedRequests = <String, ({String method, String path})>{
      r'$backup': (method: 'POST', path: r'/$backup'),
      r'$restore': (
        method: 'POST',
        path: r'/$restore',
      ),
      r'$export': (method: 'GET', path: r'/$export'),
    };

    Future<int> status(
      String token,
      String method,
      String path, {
      String? body,
    }) async {
      final res = await handler(
        testRequest(method, path, authToken: token, body: body),
      );
      return res.statusCode as int;
    }

    test('readonly user is forbidden from every privileged system op',
        () async {
      final token =
          await issueTestToken(db, role: 'readonly', scopes: ['user/*.rs']);
      for (final entry in privilegedRequests.entries) {
        final code = await status(
          token,
          entry.value.method,
          entry.value.path,
          body: entry.value.method == 'POST' ? '{}' : null,
        );
        expect(code, 403, reason: 'readonly should not reach ${entry.key}');
      }
    });

    test('clinician (user/*.* scopes) is forbidden — no system scope',
        () async {
      final token = await issueTestToken(db, scopes: ['user/*.*']);
      for (final entry in privilegedRequests.entries) {
        final code = await status(
          token,
          entry.value.method,
          entry.value.path,
          body: entry.value.method == 'POST' ? '{}' : null,
        );
        expect(code, 403, reason: 'clinician should not reach ${entry.key}');
      }
    });

    test('unauthenticated request is rejected (401)', () async {
      final res = await handler(testRequest('POST', r'/$backup', body: '{}'));
      expect(res.statusCode, 401);
    });

    test('admin passes the authorization gate (not 403)', () async {
      final token =
          await issueTestToken(db, role: 'admin', scopes: ['system/*.*']);
      for (final entry in privilegedRequests.entries) {
        final code = await status(
          token,
          entry.value.method,
          entry.value.path,
          body: entry.value.method == 'POST' ? '{}' : null,
        );
        // The op may 404/400/200 depending on state, but must clear the
        // authorization gate — never 403 for an admin.
        expect(code, isNot(403), reason: 'admin should reach ${entry.key}');
      }
    });

    test('a non-admin with an explicit system/ scope passes the gate',
        () async {
      final token = await issueTestToken(
        db,
        scopes: ['system/*.rs'],
      );
      final code = await status(token, 'GET', r'/$export');
      expect(code, isNot(403));
    });

    test(r'$restore is blocked for readonly BEFORE any DB write', () async {
      final server = await createTestServer();
      final token = await issueTestToken(
        server.db,
        role: 'readonly',
        scopes: ['user/*.rs'],
      );
      // A Bundle that would upsert a Patient if it were (wrongly) allowed.
      final bundle = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'collection',
        'entry': [
          {
            'resource': {'resourceType': 'Patient', 'id': 'should-not-exist'},
          }
        ],
      });
      final res = await server.handler(
        testRequest('POST', r'/$restore', authToken: token, body: bundle),
      );
      expect(res.statusCode, 403);
      // Confirm nothing was written.
      final got = await server.db
          .getResource(fhir.R4ResourceType.Patient, 'should-not-exist');
      expect(got, isNull);
    });
  });

  group('export job routes are answered to the owner and to system authority',
      () {
    late FhirAntDb db;
    late Handler handler;
    late Directory exportDir;

    setUp(() async {
      exportDir = await Directory.systemTemp.createTemp('authz-export');
      final server = await createTestServer(exportDir: exportDir.path);
      db = server.db;
      handler = server.handler;
      await db.saveResource(fhir.Patient(id: 'p1'.toFhirString));
    });

    tearDown(() async {
      await db.close();
      await exportDir.delete(recursive: true);
    });

    Future<String> kickoff(String token) async {
      final res = await handler(
        testRequest(
          'GET',
          r'/Patient/$export',
          authToken: token,
          headers: {'prefer': 'respond-async'},
        ),
      );
      expect(res.statusCode, 202, reason: await res.readAsString());
      final location = res.headers['content-location']!;
      return location.split('/').last;
    }

    test('the clinician who kicked a Patient export off can poll and cancel it',
        () async {
      final owner = await issueTestToken(
        db,
        username: 'owner',
        scopes: ['user/*.rs'],
      );
      final jobId = await kickoff(owner);
      final poll = await handler(
        testRequest('GET', '/\$export-poll-status/$jobId', authToken: owner),
      );
      expect(poll.statusCode, anyOf(200, 202), reason: 'the owner polls');
      final cancel = await handler(
        testRequest('DELETE', '/\$export-poll-status/$jobId', authToken: owner),
      );
      expect(cancel.statusCode, 202);
    });

    test("another clinician cannot poll, download or cancel someone's job",
        () async {
      final owner = await issueTestToken(
        db,
        username: 'owner',
        scopes: ['user/*.rs'],
      );
      final other = await issueTestToken(
        db,
        username: 'other',
        scopes: ['user/*.rs'],
      );
      final jobId = await kickoff(owner);
      for (final (method, path) in [
        ('GET', '/\$export-poll-status/$jobId'),
        ('GET', '/\$export-file/$jobId/Patient.ndjson'),
        ('DELETE', '/\$export-poll-status/$jobId'),
      ]) {
        final res = await handler(testRequest(method, path, authToken: other));
        expect(res.statusCode, 403, reason: '$method $path');
      }
    });

    test('an admin reaches any job', () async {
      final owner = await issueTestToken(
        db,
        username: 'owner',
        scopes: ['user/*.rs'],
      );
      final admin = await issueTestToken(
        db,
        username: 'admin',
        role: 'admin',
        scopes: ['system/*.*'],
      );
      final jobId = await kickoff(owner);
      final poll = await handler(
        testRequest('GET', '/\$export-poll-status/$jobId', authToken: admin),
      );
      expect(poll.statusCode, anyOf(200, 202));
    });

    test('a kick-off needs read on every type the job will write', () async {
      final groupOnly = await issueTestToken(
        db,
        username: 'grouponly',
        scopes: ['user/Group.r', 'user/Patient.r'],
      );
      final res = await handler(
        testRequest(
          'GET',
          r'/Patient/$export',
          authToken: groupOnly,
          headers: {'prefer': 'respond-async'},
        ),
      );
      expect(res.statusCode, 403, reason: await res.readAsString());
      final narrowed = await handler(
        testRequest(
          'GET',
          r'/Patient/$export?_type=Patient',
          authToken: groupOnly,
          headers: {'prefer': 'respond-async'},
        ),
      );
      expect(narrowed.statusCode, 202, reason: await narrowed.readAsString());
    });
  });
}
