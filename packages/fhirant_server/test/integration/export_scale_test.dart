import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/export_handler.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-06 finding 34 at the HTTP surface: the export file is the
/// stored JSON streamed with its length, the manifest's `Expires` is the
/// completion time plus the retention, and the sweep removes what has
/// expired and what no job owns.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String exportDir;

  setUp(() async {
    exportDir = '${Directory.systemTemp.path}/fhirant_export_scale_'
        '${DateTime.now().microsecondsSinceEpoch}';
    final server = await createTestServer(exportDir: exportDir, devMode: true);
    db = server.db;
    handler = server.handler;
  });

  tearDown(() async {
    await db.close();
    final dir = Directory(exportDir);
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  Future<String> kickOff([String path = r'/$export']) async {
    final r = await handler(
      testRequest('GET', path, headers: {'prefer': 'respond-async'}),
    );
    expect(r.statusCode, 202, reason: await r.readAsString());
    return r.headers['content-location']!.split('/').last;
  }

  Future<Response> poll(String jobId) async {
    for (var i = 0; i < 100; i++) {
      final r = await handler(
        testRequest('GET', '/\$export-poll-status/$jobId'),
      );
      if (r.statusCode != 202) return r;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    fail('export $jobId did not finish');
  }

  Map<String, dynamic> observation(int i) => {
        'resourceType': 'Observation',
        'id': 'ex$i',
        'status': 'final',
        'code': {'text': 'n$i'},
        'subject': {'reference': 'Patient/px'},
      };

  test('the file is the stored JSON, streamed with a Content-Length', () async {
    await db.saveResources([
      for (var i = 0; i < 1203; i++) fhir.Observation.fromJson(observation(i)),
    ]);
    final jobId = await kickOff(r'/$export?_type=Observation');
    final done = await poll(jobId);
    expect(done.statusCode, 200);
    final manifest =
        jsonDecode(await done.readAsString()) as Map<String, dynamic>;
    final output = (manifest['output'] as List).cast<Map<String, dynamic>>();
    expect(output, hasLength(1));
    expect(output.first['count'], 1203);

    final url = Uri.parse(output.first['url'] as String);
    final file = await handler(testRequest('GET', url.path));
    expect(file.statusCode, 200);
    final bytes = await file.read().fold<List<int>>([], (a, b) => a..addAll(b));
    expect(file.headers['content-length'], '${bytes.length}');
    final lines = const LineSplitter().convert(utf8.decode(bytes));
    expect(lines, hasLength(1203));
    final stored =
        await db.getResource(fhir.R4ResourceType.Observation, 'ex1202');
    final line = lines.firstWhere((l) => l.contains('"ex1202"'));
    expect(jsonDecode(line), stored!.toJson());
  });

  test('Expires is the completion time plus the retention', () async {
    await db.saveResource(fhir.Observation.fromJson(observation(1)));
    final jobId = await kickOff(r'/$export?_type=Observation');
    final done = await poll(jobId);
    expect(done.statusCode, 200);
    final job = await db.getExportJob(jobId);
    final expires = HttpDate.parse(done.headers['expires']!);
    expect(expires, job!.completedAt!.add(kExportRetention).toUtc());
  });

  test('the sweep removes expired jobs and orphan directories, keeps the rest',
      () async {
    await db.saveResource(fhir.Observation.fromJson(observation(1)));
    final old = await kickOff(r'/$export?_type=Observation');
    expect((await poll(old)).statusCode, 200);
    final fresh = await kickOff(r'/$export?_type=Observation');
    expect((await poll(fresh)).statusCode, 200);
    await db.updateExportJob(
      old,
      completedAt: DateTime.now().subtract(
        kExportRetention + const Duration(minutes: 1),
      ),
    );
    final orphan = Directory(
      '$exportDir/0f0f0f0f-0000-4000-8000-000000000000',
    )..createSync(recursive: true);
    final foreign = Directory('$exportDir/not-a-job')..createSync();

    expect(await sweepExpiredExports(db, exportDir), 1);

    expect(Directory('$exportDir/$old').existsSync(), isFalse);
    expect(await db.getExportJob(old), isNull);
    expect(
      (await handler(testRequest('GET', '/\$export-poll-status/$old')))
          .statusCode,
      404,
    );
    expect(Directory('$exportDir/$fresh').existsSync(), isTrue);
    expect((await db.getExportJob(fresh))!.status, 'completed');
    expect(orphan.existsSync(), isFalse);
    expect(foreign.existsSync(), isTrue);
    expect(await sweepExpiredExports(db, exportDir), 0);
  });

  test('a job left running by the last process is reported failed', () async {
    await db.createExportJob(
      jobId: '11111111-2222-4333-8444-555555555555',
      status: 'in_progress',
      requestUrl: r'http://localhost:8080/$export',
      transactionTime: DateTime.now(),
      exportLevel: 'system',
    );
    expect(await db.failStaleExportJobs('restarted'), 1);
    final r = await handler(
      testRequest(
        'GET',
        r'/$export-poll-status/11111111-2222-4333-8444-555555555555',
      ),
    );
    expect(r.statusCode, 500);
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    expect(jsonEncode(body['error']), contains('restarted'));
  });

  test('a type with no rows leaves no file and no output item', () async {
    await db.saveResource(
      fhir.Patient.fromJson({'resourceType': 'Patient', 'id': 'px'}),
    );
    final jobId = await kickOff(r'/$export?_type=Patient,Observation');
    final done = await poll(jobId);
    final manifest =
        jsonDecode(await done.readAsString()) as Map<String, dynamic>;
    final types = (manifest['output'] as List)
        .map((o) => (o as Map<String, dynamic>)['type'])
        .toList();
    expect(types, ['Patient']);
    expect(File('$exportDir/$jobId/Observation.ndjson').existsSync(), isFalse);
  });
}
