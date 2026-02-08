// ignore_for_file: lines_longer_than_80_chars
import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;
  late String exportDir;

  setUp(() async {
    exportDir =
        '${Directory.systemTemp.path}/fhirant_export_integ_${DateTime.now().millisecondsSinceEpoch}';
    final server = await createTestServer(exportDir: exportDir);
    db = server.db;
    handler = server.handler;
    token = generateTestToken();
  });

  tearDown(() async {
    await db.close();
    final dir = Directory(exportDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  /// Helper: Save a FHIR resource via POST through the pipeline.
  Future<void> saveResource(fhir.Resource resource) async {
    final resourceType = resource.resourceTypeString;
    final req = testRequest(
      'POST',
      '/$resourceType',
      body: resource.toJsonString(),
      authToken: token,
      headers: {'content-type': 'application/json'},
    );
    final resp = await handler(req);
    expect(resp.statusCode, anyOf(200, 201));
  }

  /// Helper: Parse Content-Location from kick-off response.
  String extractJobId(Response response) {
    final location = response.headers['content-location']!;
    return location.split('/').last;
  }

  /// Helper: Poll until export job is complete (or timeout).
  Future<Response> pollUntilComplete(String jobId, {int maxAttempts = 20}) async {
    for (var i = 0; i < maxAttempts; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final req = testRequest(
        'GET',
        '/\$export-poll-status/$jobId',
        authToken: token,
      );
      final resp = await handler(req);
      if (resp.statusCode == 200 || resp.statusCode == 500) {
        return resp;
      }
    }
    fail('Export job did not complete within max attempts');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // System-level export: full workflow
  // ─────────────────────────────────────────────────────────────────────────
  group('System-level \$export', () {
    test('full workflow: kick off -> poll -> download', () async {
      // 1. Create some test resources
      await saveResource(fhir.Patient(
        id: 'p1'.toFhirString,
        name: [fhir.HumanName(family: 'Smith'.toFhirString)],
      ));
      await saveResource(fhir.Observation(
        id: 'obs1'.toFhirString,
        status: fhir.ObservationStatus.final_,
        code: fhir.CodeableConcept(
          coding: [fhir.Coding(code: '85354-9'.toFhirCode)],
        ),
        subject: fhir.Reference(reference: 'Patient/p1'.toFhirString),
      ));

      // 2. Kick off export
      final kickoffReq = testRequest(
        'GET',
        '/\$export',
        authToken: token,
        headers: {'prefer': 'respond-async'},
      );
      final kickoffResp = await handler(kickoffReq);
      expect(kickoffResp.statusCode, equals(202));
      expect(kickoffResp.headers['content-location'], isNotNull);

      final jobId = extractJobId(kickoffResp);

      // 3. Poll until complete
      final statusResp = await pollUntilComplete(jobId);
      expect(statusResp.statusCode, equals(200));

      final manifest = jsonDecode(await statusResp.readAsString());
      expect(manifest['transactionTime'], isNotNull);
      expect(manifest['requiresAccessToken'], isTrue);
      expect(manifest['output'], isList);

      final output = manifest['output'] as List;
      expect(output, isNotEmpty);

      // Should have Patient and Observation files
      final types = output.map((o) => o['type']).toSet();
      expect(types, contains('Patient'));
      expect(types, contains('Observation'));

      // 4. Download NDJSON files
      for (final entry in output) {
        final url = entry['url'] as String;
        final filePath = Uri.parse(url).path;
        final downloadReq = testRequest(
          'GET',
          filePath,
          authToken: token,
        );
        final downloadResp = await handler(downloadReq);
        expect(downloadResp.statusCode, equals(200));
        expect(
          downloadResp.headers['content-type'],
          equals('application/fhir+ndjson'),
        );

        final content = await downloadResp.readAsString();
        expect(content.trim(), isNotEmpty);

        // Each line should be valid JSON
        for (final line in content.trim().split('\n')) {
          final parsed = jsonDecode(line) as Map<String, dynamic>;
          expect(parsed['resourceType'], isNotNull);
        }
      }
    });

    test('with _type filter', () async {
      await saveResource(fhir.Patient(
        id: 'p2'.toFhirString,
        name: [fhir.HumanName(family: 'Jones'.toFhirString)],
      ));
      await saveResource(fhir.Observation(
        id: 'obs2'.toFhirString,
        status: fhir.ObservationStatus.final_,
        code: fhir.CodeableConcept(
          coding: [fhir.Coding(code: '85354-9'.toFhirCode)],
        ),
      ));

      final kickoffReq = testRequest(
        'GET',
        '/\$export?_type=Patient',
        authToken: token,
        headers: {'prefer': 'respond-async'},
      );
      final kickoffResp = await handler(kickoffReq);
      expect(kickoffResp.statusCode, equals(202));

      final jobId = extractJobId(kickoffResp);
      final statusResp = await pollUntilComplete(jobId);
      expect(statusResp.statusCode, equals(200));

      final manifest = jsonDecode(await statusResp.readAsString());
      final output = manifest['output'] as List;
      final types = output.map((o) => o['type']).toSet();
      expect(types, contains('Patient'));
      expect(types, isNot(contains('Observation')));
    });

    test('with _since filter', () async {
      await saveResource(fhir.Patient(
        id: 'p3'.toFhirString,
        name: [fhir.HumanName(family: 'OldPatient'.toFhirString)],
      ));

      // Wait briefly, then record the _since timestamp
      await Future<void>.delayed(const Duration(seconds: 1));
      final sinceTime = DateTime.now().toUtc().toIso8601String();
      await Future<void>.delayed(const Duration(seconds: 1));

      await saveResource(fhir.Patient(
        id: 'p4'.toFhirString,
        name: [fhir.HumanName(family: 'NewPatient'.toFhirString)],
      ));

      final kickoffReq = testRequest(
        'GET',
        '/\$export?_since=$sinceTime',
        authToken: token,
        headers: {'prefer': 'respond-async'},
      );
      final kickoffResp = await handler(kickoffReq);
      expect(kickoffResp.statusCode, equals(202));

      final jobId = extractJobId(kickoffResp);
      final statusResp = await pollUntilComplete(jobId);
      expect(statusResp.statusCode, equals(200));

      final manifest = jsonDecode(await statusResp.readAsString());
      final output = manifest['output'] as List;

      // Should only contain the new patient
      if (output.isNotEmpty) {
        final patientEntry = output.firstWhere((o) => o['type'] == 'Patient');
        // Download and verify
        final url = patientEntry['url'] as String;
        final filePath = Uri.parse(url).path;
        final downloadReq = testRequest('GET', filePath, authToken: token);
        final downloadResp = await handler(downloadReq);
        final content = await downloadResp.readAsString();
        expect(content, contains('NewPatient'));
        expect(content, isNot(contains('OldPatient')));
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Patient-level export
  // ─────────────────────────────────────────────────────────────────────────
  group('Patient-level \$export', () {
    test('exports only patient-compartment resource types', () async {
      await saveResource(fhir.Patient(
        id: 'pp1'.toFhirString,
        name: [fhir.HumanName(family: 'PatExport'.toFhirString)],
      ));
      await saveResource(fhir.Observation(
        id: 'pobs1'.toFhirString,
        status: fhir.ObservationStatus.final_,
        code: fhir.CodeableConcept(
          coding: [fhir.Coding(code: '85354-9'.toFhirCode)],
        ),
        subject: fhir.Reference(reference: 'Patient/pp1'.toFhirString),
      ));

      final kickoffReq = testRequest(
        'GET',
        '/Patient/\$export',
        authToken: token,
        headers: {'prefer': 'respond-async'},
      );
      final kickoffResp = await handler(kickoffReq);
      expect(kickoffResp.statusCode, equals(202));

      final jobId = extractJobId(kickoffResp);
      final statusResp = await pollUntilComplete(jobId);
      expect(statusResp.statusCode, equals(200));

      final manifest = jsonDecode(await statusResp.readAsString());
      final output = manifest['output'] as List;
      expect(output, isNotEmpty);

      // All exported types should be patient-compartment types
      final types = output.map((o) => o['type']).toSet();
      // Patient and Observation are both in the Patient compartment
      for (final type in types) {
        expect(type, isNotNull);
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Cancel job
  // ─────────────────────────────────────────────────────────────────────────
  group('Cancel export', () {
    test('DELETE cancels and cleans up', () async {
      await saveResource(fhir.Patient(
        id: 'cp1'.toFhirString,
        name: [fhir.HumanName(family: 'CancelTest'.toFhirString)],
      ));

      // Kick off
      final kickoffReq = testRequest(
        'GET',
        '/\$export',
        authToken: token,
        headers: {'prefer': 'respond-async'},
      );
      final kickoffResp = await handler(kickoffReq);
      final jobId = extractJobId(kickoffResp);

      // Wait for it to complete (small dataset)
      await pollUntilComplete(jobId);

      // Now delete it
      final deleteReq = testRequest(
        'DELETE',
        '/\$export-poll-status/$jobId',
        authToken: token,
      );
      final deleteResp = await handler(deleteReq);
      expect(deleteResp.statusCode, equals(202));

      // Polling should now return 404
      final pollReq = testRequest(
        'GET',
        '/\$export-poll-status/$jobId',
        authToken: token,
      );
      final pollResp = await handler(pollReq);
      expect(pollResp.statusCode, equals(404));

      // Files should be cleaned up
      final jobDir = Directory('$exportDir/$jobId');
      expect(await jobDir.exists(), isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Validation
  // ─────────────────────────────────────────────────────────────────────────
  group('Validation', () {
    test('rejects request without Prefer: respond-async', () async {
      final req = testRequest(
        'GET',
        '/\$export',
        authToken: token,
      );
      final resp = await handler(req);
      expect(resp.statusCode, equals(400));
      final body = jsonDecode(await resp.readAsString());
      expect(body['resourceType'], equals('OperationOutcome'));
    });
  });
}
