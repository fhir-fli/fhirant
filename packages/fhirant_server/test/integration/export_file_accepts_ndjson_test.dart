import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// Bulk Data Access STU2 export.html, Bulk Data Output File Request
/// (hl7.org/fhir/uv/bulkdata/STU2/export.html, read 2026-10-17, verbatim):
/// "Accept (optional, defaults to application/fhir+ndjson)", and the
/// response "For files in ndjson format, SHALL be application/fhir+ndjson".
/// REVIEW-2026-10-17 finding 14: a client sending that Accept, as the IG
/// describes, got 406; the content negotiation knew only JSON types.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String exportDir;
  late String fileUrl;

  setUp(() async {
    exportDir = '${Directory.systemTemp.path}/fhirant_export_accept_'
        '${DateTime.now().microsecondsSinceEpoch}';
    final server = await createTestServer(exportDir: exportDir, devMode: true);
    db = server.db;
    handler = server.handler;
    await db.saveResource(fhir.Patient(id: 'p1'.toFhirString));
    final kick = await handler(
      testRequest(
        'GET',
        r'/$export?_type=Patient',
        headers: {'prefer': 'respond-async'},
      ),
    );
    final jobId = kick.headers['content-location']!.split('/').last;
    for (var i = 0; i < 100; i++) {
      final r =
          await handler(testRequest('GET', '/\$export-poll-status/$jobId'));
      if (r.statusCode == 200) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    fileUrl = '/\$export-file/$jobId/Patient.ndjson';
  });

  tearDown(() async {
    await db.close();
    final dir = Directory(exportDir);
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  for (final accept in [
    'application/fhir+ndjson',
    'application/ndjson',
    'ndjson',
    '*/*',
  ]) {
    test('a file download with Accept: $accept is 200', () async {
      final r = await handler(
        testRequest('GET', fileUrl, headers: {'accept': accept}),
      );
      expect(r.statusCode, 200, reason: await r.readAsString());
      expect(r.headers['content-type'], startsWith('application/fhir+ndjson'));
    });
  }

  test('a FHIR read asked for as ndjson is still 406', () async {
    final r = await handler(
      testRequest(
        'GET',
        '/Patient/p1',
        headers: {'accept': 'application/fhir+ndjson'},
      ),
    );
    expect(r.statusCode, 406);
  });
}
