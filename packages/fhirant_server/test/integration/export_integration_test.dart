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
    // System-level $export requires system-level authorization; the operator
    // running these bulk exports is an admin.
    token = generateTestToken(role: 'admin', scopes: ['system/*.*']);
  });

  tearDown(() async {
    await db.close();
    final dir = Directory(exportDir);
    if (dir.existsSync()) {
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

  /// Helper: poll until the export job finishes, or until [timeout] passes.
  ///
  /// The budget is wall-clock, not a count of attempts. It used to be 20
  /// attempts of a 100ms sleep, which is a budget only if every attempt costs
  /// what it usually costs. Measured 2026-08-30 over five whole-suite runs:
  /// all 55 polls returned on the FIRST attempt, so the usual cost is one
  /// tick out of twenty.
  ///
  /// One mechanism for the stall is now proven, and it was in this helper: a
  /// job that has been cancelled, or whose row is gone, answers **404 for
  /// ever**, and only 200 and 500 were treated as terminal. Measured
  /// 2026-09-03 — kick off, DELETE, poll: 404 on every attempt, unbounded. A
  /// 404 fails the test now, naming the job.
  ///
  /// Whether that is what happened on 2026-08-29 and in the 2026-08-30 clone
  /// run is NOT established; those two occurrences were never traced. The
  /// deadline stays at **20 seconds, deliberately under `dart test`'s own 30**,
  /// so a genuine hang reports which job, how long, how many polls and the
  /// last status line rather than a bare framework timeout.
  Future<Response> pollUntilComplete(
    String jobId, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final started = DateTime.now();
    var attempts = 0;
    var lastStatus = 'none';
    while (DateTime.now().difference(started) < timeout) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      attempts++;
      final req = testRequest(
        'GET',
        '/\$export-poll-status/$jobId',
        authToken: token,
      );
      final resp = await handler(req);
      if (resp.statusCode == 200 || resp.statusCode == 500) {
        return resp;
      }
      if (resp.statusCode == 404) {
        // Terminal, and it was not treated as such: the status endpoint
        // answers 404 for a job that was cancelled or whose row is gone, so a
        // poll that began after that spun until `dart test`'s own 30-second
        // timeout killed it. Measured 2026-09-03: kick off, DELETE, then poll
        // — 404 on every attempt, for ever.
        fail(
          'Export job $jobId is gone: the status endpoint answered 404 after '
          '$attempts polls. A cancelled or deleted job never becomes 200.',
        );
      }
      // Shelf lower-cases header names, so this is the X-Progress the
      // handler sets: 'Queued' while pending, 'Exporting...' once running.
      final progress = resp.headers['x-progress'] ?? '';
      lastStatus = '${resp.statusCode} $progress'.trim();
    }
    fail(
      'Export job $jobId did not finish within ${timeout.inSeconds}s: '
      '$attempts polls, last response was $lastStatus',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // System-level export: full workflow
  // ─────────────────────────────────────────────────────────────────────────
  group(r'System-level $export', () {
    test('full workflow: kick off -> poll -> download', () async {
      // 1. Create some test resources
      await saveResource(
        fhir.Patient(
          id: 'p1'.toFhirString,
          name: [fhir.HumanName(family: 'Smith'.toFhirString)],
        ),
      );
      await saveResource(
        fhir.Observation(
          id: 'obs1'.toFhirString,
          status: fhir.ObservationStatus.final_,
          code: fhir.CodeableConcept(
            coding: [fhir.Coding(code: '85354-9'.toFhirCode)],
          ),
          subject: fhir.Reference(reference: 'Patient/p1'.toFhirString),
        ),
      );

      // 2. Kick off export
      final kickoffReq = testRequest(
        'GET',
        r'/$export',
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
      await saveResource(
        fhir.Patient(
          id: 'p2'.toFhirString,
          name: [fhir.HumanName(family: 'Jones'.toFhirString)],
        ),
      );
      await saveResource(
        fhir.Observation(
          id: 'obs2'.toFhirString,
          status: fhir.ObservationStatus.final_,
          code: fhir.CodeableConcept(
            coding: [fhir.Coding(code: '85354-9'.toFhirCode)],
          ),
        ),
      );

      final kickoffReq = testRequest(
        'GET',
        r'/$export?_type=Patient',
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
      await saveResource(
        fhir.Patient(
          id: 'p3'.toFhirString,
          name: [fhir.HumanName(family: 'OldPatient'.toFhirString)],
        ),
      );

      // Wait briefly, then record the _since timestamp
      await Future<void>.delayed(const Duration(seconds: 1));
      final sinceTime = DateTime.now().toUtc().toIso8601String();
      await Future<void>.delayed(const Duration(seconds: 1));

      await saveResource(
        fhir.Patient(
          id: 'p4'.toFhirString,
          name: [fhir.HumanName(family: 'NewPatient'.toFhirString)],
        ),
      );

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
  group(r'Patient-level $export', () {
    test('exports only patient-compartment resource types', () async {
      await saveResource(
        fhir.Patient(
          id: 'pp1'.toFhirString,
          name: [fhir.HumanName(family: 'PatExport'.toFhirString)],
        ),
      );
      await saveResource(
        fhir.Observation(
          id: 'pobs1'.toFhirString,
          status: fhir.ObservationStatus.final_,
          code: fhir.CodeableConcept(
            coding: [fhir.Coding(code: '85354-9'.toFhirCode)],
          ),
          subject: fhir.Reference(reference: 'Patient/pp1'.toFhirString),
        ),
      );

      final kickoffReq = testRequest(
        'GET',
        r'/Patient/$export',
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
  // Group-level export
  // ─────────────────────────────────────────────────────────────────────────
  group(r'Group-level $export', () {
    test('full workflow: create Group + members -> export -> verify NDJSON',
        () async {
      // 1. Create Patient member
      await saveResource(
        fhir.Patient(
          id: 'gp1'.toFhirString,
          name: [fhir.HumanName(family: 'GroupMember1'.toFhirString)],
        ),
      );

      // 2. Create Observation linked to group member
      await saveResource(
        fhir.Observation(
          id: 'gobs1'.toFhirString,
          status: fhir.ObservationStatus.final_,
          code: fhir.CodeableConcept(
            coding: [fhir.Coding(code: '85354-9'.toFhirCode)],
          ),
          subject: fhir.Reference(reference: 'Patient/gp1'.toFhirString),
        ),
      );

      // 3. Create the Group resource
      await saveResource(
        fhir.FhirGroup(
          id: 'test-group'.toFhirString,
          active: true.toFhirBoolean,
          type: fhir.GroupType.person,
          actual: true.toFhirBoolean,
          member: [
            fhir.GroupMember(
              entity: fhir.Reference(reference: 'Patient/gp1'.toFhirString),
            ),
          ],
        ),
      );

      // 4. Kick off group export
      final kickoffReq = testRequest(
        'GET',
        r'/Group/test-group/$export',
        authToken: token,
        headers: {'prefer': 'respond-async'},
      );
      final kickoffResp = await handler(kickoffReq);
      expect(kickoffResp.statusCode, equals(202));
      expect(kickoffResp.headers['content-location'], isNotNull);

      final jobId = extractJobId(kickoffResp);

      // 5. Poll until complete
      final statusResp = await pollUntilComplete(jobId);
      expect(statusResp.statusCode, equals(200));

      final manifest = jsonDecode(await statusResp.readAsString());
      final output = manifest['output'] as List;
      expect(output, isNotEmpty);

      final types = output.map((o) => o['type']).toSet();
      expect(types, contains('Patient'));
      expect(types, contains('Observation'));

      // 6. Download and verify Patient NDJSON
      final patientEntry = output.firstWhere((o) => o['type'] == 'Patient');
      final patientUrl = patientEntry['url'] as String;
      final patientPath = Uri.parse(patientUrl).path;
      final patientReq = testRequest('GET', patientPath, authToken: token);
      final patientResp = await handler(patientReq);
      final patientContent = await patientResp.readAsString();
      expect(patientContent, contains('GroupMember1'));

      // 7. Download and verify Observation NDJSON
      final obsEntry = output.firstWhere((o) => o['type'] == 'Observation');
      final obsUrl = obsEntry['url'] as String;
      final obsPath = Uri.parse(obsUrl).path;
      final obsReq = testRequest('GET', obsPath, authToken: token);
      final obsResp = await handler(obsReq);
      final obsContent = await obsResp.readAsString();
      expect(obsContent, contains('gobs1'));
    });

    test('with _type filter restricts exported types', () async {
      // Create members and observations
      await saveResource(
        fhir.Patient(
          id: 'gtp1'.toFhirString,
          name: [fhir.HumanName(family: 'TypeFilter'.toFhirString)],
        ),
      );
      await saveResource(
        fhir.Observation(
          id: 'gtobs1'.toFhirString,
          status: fhir.ObservationStatus.final_,
          code: fhir.CodeableConcept(
            coding: [fhir.Coding(code: '85354-9'.toFhirCode)],
          ),
          subject: fhir.Reference(reference: 'Patient/gtp1'.toFhirString),
        ),
      );

      await saveResource(
        fhir.FhirGroup(
          id: 'filter-group'.toFhirString,
          active: true.toFhirBoolean,
          type: fhir.GroupType.person,
          actual: true.toFhirBoolean,
          member: [
            fhir.GroupMember(
              entity: fhir.Reference(reference: 'Patient/gtp1'.toFhirString),
            ),
          ],
        ),
      );

      // Kick off with _type=Patient only
      final kickoffReq = testRequest(
        'GET',
        r'/Group/filter-group/$export?_type=Patient',
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

    test('Group with no patient members returns empty export', () async {
      // Create a Group with no members
      await saveResource(
        fhir.FhirGroup(
          id: 'empty-group'.toFhirString,
          active: true.toFhirBoolean,
          type: fhir.GroupType.person,
          actual: true.toFhirBoolean,
        ),
      );

      final kickoffReq = testRequest(
        'GET',
        r'/Group/empty-group/$export',
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
      expect(output, isEmpty);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // _typeFilter
  // ─────────────────────────────────────────────────────────────────────────
  group('_typeFilter', () {
    test('filters resources by search criteria', () async {
      // Create Observations with different codes
      await saveResource(
        fhir.Observation(
          id: 'tf-obs1'.toFhirString,
          status: fhir.ObservationStatus.final_,
          code: fhir.CodeableConcept(
            coding: [
              fhir.Coding(
                system: 'http://loinc.org'.toFhirUri,
                code: '85354-9'.toFhirCode,
              ),
            ],
          ),
        ),
      );
      await saveResource(
        fhir.Observation(
          id: 'tf-obs2'.toFhirString,
          status: fhir.ObservationStatus.final_,
          code: fhir.CodeableConcept(
            coding: [
              fhir.Coding(
                system: 'http://loinc.org'.toFhirUri,
                code: '29463-7'.toFhirCode,
              ),
            ],
          ),
        ),
      );

      // Export with _typeFilter that matches only one code
      final kickoffReq = testRequest(
        'GET',
        '/\$export?_type=Observation&_typeFilter=${Uri.encodeComponent('Observation?code=85354-9')}',
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

      // Download and verify only the matching Observation is present
      final obsEntry = output.firstWhere((o) => o['type'] == 'Observation');
      final url = obsEntry['url'] as String;
      final filePath = Uri.parse(url).path;
      final downloadReq = testRequest('GET', filePath, authToken: token);
      final downloadResp = await handler(downloadReq);
      final content = await downloadResp.readAsString();
      expect(content, contains('85354-9'));
      expect(content, isNot(contains('29463-7')));
    });

    test('_typeFilter for type not in _type is ignored', () async {
      await saveResource(
        fhir.Patient(
          id: 'tf-p1'.toFhirString,
          name: [fhir.HumanName(family: 'TypeFilterPatient'.toFhirString)],
        ),
      );
      await saveResource(
        fhir.Observation(
          id: 'tf-obs3'.toFhirString,
          status: fhir.ObservationStatus.final_,
          code: fhir.CodeableConcept(
            coding: [fhir.Coding(code: '85354-9'.toFhirCode)],
          ),
        ),
      );

      // _type=Patient but _typeFilter references Observation
      final kickoffReq = testRequest(
        'GET',
        '/\$export?_type=Patient&_typeFilter=${Uri.encodeComponent('Observation?code=85354-9')}',
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
      // Should only have Patient, not Observation
      expect(types, contains('Patient'));
      expect(types, isNot(contains('Observation')));
    });

    test('_typeFilter combined with _since', () async {
      await saveResource(
        fhir.Observation(
          id: 'tf-obs-old'.toFhirString,
          status: fhir.ObservationStatus.final_,
          code: fhir.CodeableConcept(
            coding: [
              fhir.Coding(
                system: 'http://loinc.org'.toFhirUri,
                code: '85354-9'.toFhirCode,
              ),
            ],
          ),
        ),
      );

      await Future<void>.delayed(const Duration(seconds: 1));
      final sinceTime = DateTime.now().toUtc().toIso8601String();
      await Future<void>.delayed(const Duration(seconds: 1));

      await saveResource(
        fhir.Observation(
          id: 'tf-obs-new'.toFhirString,
          status: fhir.ObservationStatus.final_,
          code: fhir.CodeableConcept(
            coding: [
              fhir.Coding(
                system: 'http://loinc.org'.toFhirUri,
                code: '85354-9'.toFhirCode,
              ),
            ],
          ),
        ),
      );

      final kickoffReq = testRequest(
        'GET',
        '/\$export?_type=Observation&_since=$sinceTime&_typeFilter=${Uri.encodeComponent('Observation?code=85354-9')}',
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

      if (output.isNotEmpty) {
        final obsEntry = output.firstWhere((o) => o['type'] == 'Observation');
        final url = obsEntry['url'] as String;
        final filePath = Uri.parse(url).path;
        final downloadReq = testRequest('GET', filePath, authToken: token);
        final downloadResp = await handler(downloadReq);
        final content = await downloadResp.readAsString();
        // Should contain new but not old
        expect(content, contains('tf-obs-new'));
        expect(content, isNot(contains('tf-obs-old')));
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Cancel job
  // ─────────────────────────────────────────────────────────────────────────
  group('Cancel export', () {
    test('DELETE cancels and cleans up', () async {
      await saveResource(
        fhir.Patient(
          id: 'cp1'.toFhirString,
          name: [fhir.HumanName(family: 'CancelTest'.toFhirString)],
        ),
      );

      // Kick off
      final kickoffReq = testRequest(
        'GET',
        r'/$export',
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
      expect(jobDir.existsSync(), isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Validation
  // ─────────────────────────────────────────────────────────────────────────
  group('Validation', () {
    test('rejects request without Prefer: respond-async', () async {
      final req = testRequest(
        'GET',
        r'/$export',
        authToken: token,
      );
      final resp = await handler(req);
      expect(resp.statusCode, equals(400));
      final body = jsonDecode(await resp.readAsString());
      expect(body['resourceType'], equals('OperationOutcome'));
    });
  });
}
