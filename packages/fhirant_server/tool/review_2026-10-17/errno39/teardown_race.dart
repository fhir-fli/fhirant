// Measures the teardown race behind system_operation_authz_test's
// "Directory not empty, errno = 39" (failed once in a full run 2026-10-21;
// log beside this file). Hypothesis: the test ends while the export job it
// kicked off still runs, and the job creates a type's file under the export
// directory while tearDown's recursive delete is emptying it.
//
// Each iteration repeats that group's setUp and tearDown around one
// Patient-level kick-off, with [rows] Observations so the job is still
// walking the compartment's types at teardown. Arm A tears down at once, as
// the test does; arm B waits for the job to end first. One row per iteration
// to teardown_race.tsv, written and flushed as it runs.
//
// Run from packages/fhirant_server:
//   dart run tool/review_2026-10-17/errno39/teardown_race.dart <iterations> <rows>
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;

import '../../../test/integration/test_helpers.dart';

Future<void> main(List<String> args) async {
  final iterations = int.parse(args[0]);
  final rows = int.parse(args[1]);
  final out = File('tool/review_2026-10-17/errno39/teardown_race.tsv')
      .openSync(mode: FileMode.write)
    ..writeStringSync('arm\titeration\trows\tresult\n')
    ..flushSync();
  for (var i = 0; i < iterations; i++) {
    for (final arm in ['A-no-wait', 'B-wait-for-job']) {
      final result = await _once(rows, waitForJob: arm.startsWith('B'));
      final row = '$arm\t$i\t$rows\t$result';
      out
        ..writeStringSync('$row\n')
        ..flushSync();
      stdout.writeln(row);
    }
  }
  out.closeSync();
}

Future<String> _once(int rows, {required bool waitForJob}) async {
  final exportDir = await Directory.systemTemp.createTemp('authz-export');
  final server = await createTestServer(exportDir: exportDir.path);
  final db = server.db;
  await db.saveResource(fhir.Patient(id: 'p1'.toFhirString));
  for (var i = 0; i < rows; i++) {
    await db.saveResource(
      fhir.Resource.fromJson({
        'resourceType': 'Observation',
        'id': 'o$i',
        'status': 'final',
        'code': {'text': 'x'},
        'subject': {'reference': 'Patient/p1'},
      }),
    );
  }
  final owner = await issueTestToken(
    db,
    username: 'owner',
    scopes: ['user/*.rs'],
  );
  final kick = await server.handler(
    testRequest(
      'GET',
      r'/Patient/$export',
      authToken: owner,
      headers: {'prefer': 'respond-async'},
    ),
  );
  final jobId = kick.headers['content-location']!.split('/').last;
  if (waitForJob) {
    await pollExport(server.handler, jobId, authToken: owner);
  }
  await db.close();
  try {
    await exportDir.delete(recursive: true);
    return 'clean';
  } on FileSystemException catch (e) {
    if (exportDir.existsSync()) {
      // Leave no state behind once the job has stopped.
      await Future<void>.delayed(const Duration(seconds: 2));
      if (exportDir.existsSync()) await exportDir.delete(recursive: true);
    }
    return 'errno ${e.osError?.errorCode}: ${e.osError?.message}';
  }
}
