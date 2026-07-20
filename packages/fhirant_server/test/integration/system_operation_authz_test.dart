import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:test/test.dart';

import 'test_helpers.dart';

/// Verifies that privileged root-level system operations ($backup/$restore/
/// $export…) are gated to system-level (admin) callers through the full
/// middleware pipeline — not reachable by ordinary authenticated users.
void main() {
  group('System operation authorization', () {
    late dynamic handler;

    setUp(() async {
      final server = await createTestServer();
      handler = server.handler;
    });

    // A representative destructive/full-DB operation from each category.
    final privilegedRequests = <String, ({String method, String path})>{
      r'$backup': (method: 'POST', path: r'/$backup'),
      r'$restore': (
        method: 'POST',
        path: r'/$restore',
      ),
      r'$export': (method: 'GET', path: r'/$export'),
      r'$export-file': (
        method: 'GET',
        path: r'/$export-file/job1/Patient.ndjson',
      ),
    };

    Future<int> status(String token, String method, String path,
        {String? body}) async {
      final res = await handler(
        testRequest(method, path, authToken: token, body: body),
      );
      return res.statusCode as int;
    }

    test('readonly user is forbidden from every privileged system op',
        () async {
      final token = generateTestToken(role: 'readonly', scopes: ['user/*.rs']);
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
      final token = generateTestToken(role: 'clinician', scopes: ['user/*.*']);
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
      final token = generateTestToken(role: 'admin', scopes: ['system/*.*']);
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
      final token = generateTestToken(
        role: 'clinician',
        scopes: ['system/*.rs'],
      );
      final code = await status(token, 'GET', r'/$export');
      expect(code, isNot(403));
    });

    test(r'$restore is blocked for readonly BEFORE any DB write', () async {
      final server = await createTestServer();
      final token = generateTestToken(role: 'readonly', scopes: ['user/*.rs']);
      // A Bundle that would upsert a Patient if it were (wrongly) allowed.
      final bundle = jsonEncode({
        'resourceType': 'Bundle',
        'type': 'collection',
        'entry': [
          {
            'resource': {'resourceType': 'Patient', 'id': 'should-not-exist'}
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
}
