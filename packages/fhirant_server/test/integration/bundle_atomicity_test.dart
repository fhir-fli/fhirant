import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:test/test.dart';

import 'test_helpers.dart';

/// Evidence for finding F11 of SECURITY-REVIEW-2026-08-25.md.
///
/// FHIR requires a `transaction` Bundle to be all-or-nothing. That used to be
/// attempted by hand — apply each entry, and on failure walk back through the
/// applied ones re-saving their previous state — which is best-effort by
/// construction: the compensating writes can themselves fail, and the code
/// logged exactly that case.
///
/// Atomicity is only observable against a real database, so these run the full
/// pipeline over in-memory SQLite rather than a mock. A mock can show that
/// rollback was *called*; only a database can show the row is gone.
void main() {
  Map<String, dynamic> entry(String method, String url, [String? id]) => {
        if (id != null)
          'resource': {'resourceType': 'Patient', 'id': id}
        else
          'resource': {'resourceType': 'Patient'},
        'request': {'method': method, 'url': url},
      };

  test('a transaction Bundle that fails part-way leaves nothing behind',
      () async {
    final server = await createTestServer();
    final token = generateTestToken(scopes: ['user/*.cruds']);

    // Two entries that would succeed, then one the server must refuse: a PUT
    // whose URL names a different id than the resource it carries.
    final bundle = {
      'resourceType': 'Bundle',
      'type': 'transaction',
      'entry': [
        entry('PUT', 'Patient/keep-1', 'keep-1'),
        entry('PUT', 'Patient/keep-2', 'keep-2'),
        {
          'resource': {'resourceType': 'Patient', 'id': 'mismatch-a'},
          'request': {'method': 'PUT', 'url': 'Patient/mismatch-b'},
        },
      ],
    };

    final response = await server.handler(
      testRequest('POST', '/', body: jsonEncode(bundle), authToken: token),
    );

    expect(
      response.statusCode,
      greaterThanOrEqualTo(400),
      reason: 'the transaction must be refused, not partially applied',
    );

    // The two that "succeeded" must not survive. This is the assertion the
    // manual rollback could only ever attempt.
    for (final id in ['keep-1', 'keep-2']) {
      final found =
          await server.db.getResource(fhir.R4ResourceType.Patient, id);
      expect(
        found,
        isNull,
        reason: 'Patient/$id was written by an entry before the failure and '
            'must have been rolled back with it',
      );
    }
  });

  test('a transaction Bundle that succeeds commits every entry', () async {
    // The other half of the guarantee: rollback must not be so eager that a
    // good Bundle loses work.
    final server = await createTestServer();
    final token = generateTestToken(scopes: ['user/*.cruds']);

    final bundle = {
      'resourceType': 'Bundle',
      'type': 'transaction',
      'entry': [
        entry('PUT', 'Patient/good-1', 'good-1'),
        entry('PUT', 'Patient/good-2', 'good-2'),
        entry('PUT', 'Patient/good-3', 'good-3'),
      ],
    };

    final response = await server.handler(
      testRequest('POST', '/', body: jsonEncode(bundle), authToken: token),
    );

    expect(response.statusCode, equals(200));
    for (final id in ['good-1', 'good-2', 'good-3']) {
      final found =
          await server.db.getResource(fhir.R4ResourceType.Patient, id);
      expect(found, isNotNull, reason: 'Patient/$id should have committed');
    }
  });

  test('a batch Bundle keeps what worked when one entry fails', () async {
    // A batch is explicitly NOT atomic — the entries are independent requests
    // that happen to share an envelope. Sharing a database transaction for
    // speed must not quietly turn it into all-or-nothing.
    final server = await createTestServer();
    final token = generateTestToken(scopes: ['user/*.cruds']);

    final bundle = {
      'resourceType': 'Bundle',
      'type': 'batch',
      'entry': [
        entry('PUT', 'Patient/batch-1', 'batch-1'),
        {
          'resource': {'resourceType': 'Patient', 'id': 'mismatch-a'},
          'request': {'method': 'PUT', 'url': 'Patient/mismatch-b'},
        },
        entry('PUT', 'Patient/batch-3', 'batch-3'),
      ],
    };

    final response = await server.handler(
      testRequest('POST', '/', body: jsonEncode(bundle), authToken: token),
    );

    expect(response.statusCode, equals(200));
    for (final id in ['batch-1', 'batch-3']) {
      final found =
          await server.db.getResource(fhir.R4ResourceType.Patient, id);
      expect(
        found,
        isNotNull,
        reason: 'Patient/$id succeeded on its own and a sibling failing must '
            'not undo it',
      );
    }
  });
}
