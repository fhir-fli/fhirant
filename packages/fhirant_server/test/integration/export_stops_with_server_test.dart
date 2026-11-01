import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:fhirant_server/src/handlers/export_handler.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// Stopping the server ends a running `$export` before the store closes
/// (ExportJobs, export_handler.dart). A job ran after its kick-off was
/// answered and nothing held it: `stop()` drained the audit and Subscription
/// queues and left the job running against a store about to close, writing
/// into its directory (`tool/review_2026-10-17/errno39/repeat_authz.tsv`:
/// a test's tearDown deleted that directory under the job, 1 run in 40).
/// Bulk Data export.html: a job that fails answers its status request with
/// an error and an OperationOutcome, so the job ended here is failed with
/// the reason rather than left in progress.
void main() {
  test('stop ends a running export, failed with the reason, files removed',
      () async {
    final db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
    final exportDir = await Directory.systemTemp.createTemp('export-stop');
    addTearDown(() async {
      await db.close();
      await exportDir.delete(recursive: true);
    });
    // Three types of 1,000 each, so the job is still writing when stop runs.
    final saved = await db.saveResources([
      for (var i = 0; i < 1000; i++) ...[
        fhir.Patient(id: fhir.FhirString('p$i')),
        fhir.Observation(
          id: fhir.FhirString('o$i'),
          status: fhir.ObservationStatus.final_,
          code: fhir.CodeableConcept(text: fhir.FhirString('probe $i')),
          subject: fhir.Reference(reference: fhir.FhirString('Patient/p$i')),
        ),
        fhir.Condition(
          id: fhir.FhirString('c$i'),
          subject: fhir.Reference(reference: fhir.FhirString('Patient/p$i')),
        ),
      ],
    ]);
    expect(saved, isTrue);

    final server = FhirAntServer(
      db,
      jwtSecret: 'test-secret',
      devMode: true,
      exportDir: exportDir.path,
    );
    await server.startHttp(0);
    final kickoff = await http.get(
      Uri.parse('http://127.0.0.1:${server.port}/\$export'),
      headers: {'prefer': 'respond-async', 'accept': 'application/fhir+json'},
    );
    expect(kickoff.statusCode, 202, reason: kickoff.body);
    final jobId = kickoff.headers['content-location']!.split('/').last;

    await server.stop();

    expect(server.exportJobs.running, 0);
    final job = await db.getExportJob(jobId);
    expect(job?.status, 'error', reason: 'status ${job?.status}');
    expect(job?.errorJson, contains(exportStoppedMessage));
    expect(Directory('${exportDir.path}/$jobId').existsSync(), isFalse);
  });
}
