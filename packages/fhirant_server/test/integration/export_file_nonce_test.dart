import 'dart:io';
import 'dart:typed_data';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/export_file_crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// NIST SP 800-38D (nvlpubs.nist.gov/nistpubs/Legacy/SP/
/// nistspecialpublication800-38d.pdf, read 2026-10-21, verbatim), 8.2: for
/// a 96-bit IV "exactly one of the constructions, but not both, shall be
/// used, across all instances of the authenticated encryption function
/// with the given key." 8.2.2 needs a random field of "at least 96 bits";
/// 8.2.1 a fixed field where "For any given key, no two distinct devices
/// shall share the same fixed field", arbitrary bits only "when there is
/// only one context to identify". An export job encrypts one file per
/// resource type under one key, and each file's 64-bit fixed field was
/// random: neither construction (ASVS 5.0.0 V11.3.4, REVIEW-2026-10-17).
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String exportDir;

  setUp(() async {
    exportDir = '${Directory.systemTemp.path}/fhirant_export_nonce_'
        '${DateTime.now().microsecondsSinceEpoch}';
    final server = await createTestServer(exportDir: exportDir, devMode: true);
    db = server.db;
    handler = server.handler;
    for (final r in <Map<String, dynamic>>[
      {'resourceType': 'Patient', 'id': 'p1'},
      {
        'resourceType': 'Observation',
        'id': 'o1',
        'status': 'final',
        'code': {'text': 'x'},
        'subject': {'reference': 'Patient/p1'},
      },
      {
        'resourceType': 'Condition',
        'id': 'c1',
        'subject': {'reference': 'Patient/p1'},
      },
    ]) {
      await db.saveResource(fhir.Resource.fromJson(r));
    }
  });

  tearDown(() async {
    await db.close();
    final dir = Directory(exportDir);
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  /// The fixed field of each file the export at [path] wrote, by type.
  Future<Map<String, Uint8List>> fixedFields(String path) async {
    final kick = await handler(
      testRequest('GET', path, headers: {'prefer': 'respond-async'}),
    );
    expect(kick.statusCode, 202, reason: await kick.readAsString());
    final jobId = kick.headers['content-location']!.split('/').last;
    expect((await pollExport(handler, jobId)).statusCode, 200);
    return {
      for (final file in Directory('$exportDir/$jobId').listSync())
        if (file is File && file.path.endsWith('.ndjson'))
          file.uri.pathSegments.last.replaceAll('.ndjson', ''):
              Uint8List.sublistView(
            file.readAsBytesSync(),
            ExportFileCrypto.headerLength - 8,
            ExportFileCrypto.headerLength,
          ),
    };
  }

  /// The type's index, as the 8-byte big-endian fixed field.
  Uint8List field(String type) => Uint8List(8)
    ..buffer
        .asByteData()
        .setUint64(0, fhir.R4ResourceType.fromString(type)!.index);

  for (final path in [r'/$export', r'/Patient/$export']) {
    test('$path: each file under the job key has its own fixed field',
        () async {
      final got = await fixedFields(path);
      expect(got.keys, containsAll(['Patient', 'Observation', 'Condition']));
      for (final MapEntry(key: type, value: bytes) in got.entries) {
        expect(bytes, field(type), reason: type);
      }
    });
  }
}
