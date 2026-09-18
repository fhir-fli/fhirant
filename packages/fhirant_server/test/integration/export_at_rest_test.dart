import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-17 A8. After `$export`, `Patient.ndjson` under the export
/// directory held the patient's name in the clear for 24 hours, beside an
/// encrypted store; in the app that directory is under Documents, which
/// iOS backs up. The files are the export's snapshot (Bulk Data 2.0.0
/// export.html, read whole 2026-09-18, on `transactionTime`: "The response
/// SHOULD NOT include any resources modified after this instant, and SHALL
/// include any matching resources modified up to and including this
/// instant"), so they stay; they are now written under a key the job
/// holds inside the store, and decrypted as they are served.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;
  late String exportDir;

  setUp(() async {
    exportDir =
        (await Directory.systemTemp.createTemp('fhirant_export_rest_')).path;
    final server = await createTestServer(exportDir: exportDir);
    db = server.db;
    handler = server.handler;
    token = await issueTestToken(db, role: 'admin', scopes: ['system/*.*']);
  });

  tearDown(() async {
    await db.close();
    await Directory(exportDir).delete(recursive: true);
  });

  Future<Response> send(String method, String path, {String? prefer}) async =>
      handler(
        testRequest(
          method,
          path,
          authToken: token,
          headers: {if (prefer != null) 'prefer': prefer},
        ),
      );

  Future<(String jobId, Map<String, dynamic> manifest)> export() async {
    final kickoff = await send('GET', r'/$export', prefer: 'respond-async');
    expect(kickoff.statusCode, 202);
    final jobId = kickoff.headers['content-location']!.split('/').last;
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (true) {
      final status = await send('GET', '/\$export-poll-status/$jobId');
      if (status.statusCode == 200) {
        return (
          jobId,
          jsonDecode(await status.readAsString()) as Map<String, dynamic>,
        );
      }
      expect(status.statusCode, 202, reason: await status.readAsString());
      expect(DateTime.now().isBefore(deadline), isTrue, reason: 'stalled');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  test('the file on disk holds no plaintext; the download is the NDJSON',
      () async {
    await db.saveResource(
      fhir.Patient(
        id: 'p1'.toFhirString,
        name: [fhir.HumanName(family: 'Okwonga'.toFhirString)],
      ),
    );
    final (jobId, manifest) = await export();
    final output = (manifest['output'] as List).cast<Map<String, dynamic>>();
    expect(output.map((o) => o['type']), ['Patient']);
    expect(output.single['count'], 1);

    final onDisk = File('$exportDir/$jobId/Patient.ndjson');
    expect(onDisk.existsSync(), isTrue);
    final bytes = await onDisk.readAsBytes();
    final text = latin1.decode(bytes, allowInvalid: true);
    expect(text, isNot(contains('Okwonga')));
    expect(text, isNot(contains('Patient')));

    final download = await send(
      'GET',
      Uri.parse(output.single['url'] as String).path,
    );
    expect(download.statusCode, 200);
    expect(download.headers['content-type'], 'application/fhir+ndjson');
    final lines = (await download.readAsString()).trim().split('\n');
    expect(lines, hasLength(1));
    final patient = jsonDecode(lines.single) as Map<String, dynamic>;
    expect(patient['id'], 'p1');
    expect((patient['name'] as List).first['family'], 'Okwonga');
  });

  test('a file changed on disk is refused, not served in part', () async {
    await db.saveResource(fhir.Patient(id: 'p1'.toFhirString));
    final (jobId, manifest) = await export();
    final url = (manifest['output'] as List).first['url'] as String;
    final onDisk = File('$exportDir/$jobId/Patient.ndjson');
    final bytes = await onDisk.readAsBytes();
    bytes[bytes.length - 3] ^= 0x01;
    await onDisk.writeAsBytes(bytes);

    final download = await send('GET', Uri.parse(url).path);
    // Refused whole: the tag fails before any byte of the frame is sent.
    expect(download.statusCode, isNot(200));
  });

  test('a file cut short on disk is refused, not served in part', () async {
    await db.saveResource(fhir.Patient(id: 'p1'.toFhirString));
    final (jobId, manifest) = await export();
    final url = (manifest['output'] as List).first['url'] as String;
    final onDisk = File('$exportDir/$jobId/Patient.ndjson');
    final bytes = await onDisk.readAsBytes();
    await onDisk.writeAsBytes(bytes.sublist(0, bytes.length ~/ 2));

    final download = await send('GET', Uri.parse(url).path);
    expect(download.statusCode, isNot(200));
  });
}
