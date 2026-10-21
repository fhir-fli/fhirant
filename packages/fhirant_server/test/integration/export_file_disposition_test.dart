import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// OWASP ASVS 5.0.0 V5.4.1 (L2, read 2026-10-21, verbatim): "Verify that
/// the application validates or ignores user-submitted filenames ... and
/// specifies a filename in the Content-Disposition header field in the
/// response." V5.4.2: file names served in header fields "are encoded or
/// sanitized (e.g., following RFC 6266)". An export file download carried
/// no Content-Disposition (REVIEW-2026-10-17, ASVS walk).
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String exportDir;

  setUp(() async {
    exportDir = '${Directory.systemTemp.path}/fhirant_export_disposition_'
        '${DateTime.now().microsecondsSinceEpoch}';
    final server = await createTestServer(exportDir: exportDir, devMode: true);
    db = server.db;
    handler = server.handler;
    await db.saveResource(
      fhir.Resource.fromJson({'resourceType': 'Patient', 'id': 'p1'}),
    );
  });

  tearDown(() async {
    await db.close();
    final dir = Directory(exportDir);
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('an export file is served as an attachment named for its file',
      () async {
    final kick = await handler(
      testRequest('GET', r'/$export', headers: {'prefer': 'respond-async'}),
    );
    expect(kick.statusCode, 202, reason: await kick.readAsString());
    final jobId = kick.headers['content-location']!.split('/').last;
    final done = await pollExport(handler, jobId);
    final manifest =
        jsonDecode(await done.readAsString()) as Map<String, dynamic>;
    final url = (manifest['output'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((o) => o['type'] == 'Patient')['url'] as String;

    final file = await handler(testRequest('GET', Uri.parse(url).path));
    expect(file.statusCode, 200);
    expect(
      file.headers['content-disposition'],
      'attachment; filename="Patient.ndjson"',
    );
    expect(await file.readAsString(), contains('"id":"p1"'));
  });
}
