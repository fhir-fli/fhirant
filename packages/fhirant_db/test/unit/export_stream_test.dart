import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:test/test.dart';

/// REVIEW-2026-09-06 finding 34: `$export` streams the stored JSON a page
/// at a time, and finished jobs are found for the sweep.
void main() {
  late FhirAntDb db;

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
  });

  tearDown(() => db.close());

  fhir.Observation obs(int i) => fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': 'o${i.toString().padLeft(5, '0')}',
        'status': 'final',
        'code': {'text': 'n$i'},
      });

  group('exportJson', () {
    test(
        'every resource of the type, once, across page boundaries, as '
        'stored', () async {
      await db.saveResources([for (var i = 0; i < 1201; i++) obs(i)]);
      final lines =
          await db.exportJson(fhir.R4ResourceType.Observation).toList();
      expect(lines, hasLength(1201));
      final ids = lines
          .map((l) => (jsonDecode(l) as Map<String, dynamic>)['id'])
          .toSet();
      expect(ids, hasLength(1201));
      final stored = await db.getResource(
        fhir.R4ResourceType.Observation,
        'o00007',
      );
      final line = lines.firstWhere((l) => l.contains('"o00007"'));
      expect(jsonDecode(line), stored!.toJson());
    });

    test('a page size that divides the count exactly ends cleanly', () async {
      await db.saveResources([for (var i = 0; i < 1000; i++) obs(i)]);
      expect(
        await db.exportJson(fhir.R4ResourceType.Observation).length,
        1000,
      );
    });

    test('since keeps last_updated at or after it, in SQL', () async {
      await db.saveResources([for (var i = 0; i < 5; i++) obs(i)]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final cut = DateTime.now();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await db.saveResources([for (var i = 5; i < 8; i++) obs(i)]);
      final lines = await db
          .exportJson(fhir.R4ResourceType.Observation, since: cut)
          .toList();
      expect(lines, hasLength(3));
    });

    test('ids: only those, in id order, chunked above the page size', () async {
      await db.saveResources([for (var i = 0; i < 1100; i++) obs(i)]);
      final wanted = [
        for (var i = 1099; i >= 0; i -= 1)
          if (i.isEven) 'o${i.toString().padLeft(5, '0')}',
        'not-there',
      ];
      final lines = await db
          .exportJson(fhir.R4ResourceType.Observation, ids: wanted)
          .toList();
      final ids = lines
          .map((l) => (jsonDecode(l) as Map<String, dynamic>)['id'] as String)
          .toList();
      expect(ids, hasLength(550));
      expect(ids, [...ids]..sort());
      expect(ids.first, 'o00000');
      expect(ids.last, 'o01098');
    });

    test('another type is not in the stream', () async {
      await db.saveResource(
        fhir.Patient.fromJson({'resourceType': 'Patient', 'id': 'p'}),
      );
      await db.saveResource(obs(1));
      expect(await db.exportJson(fhir.R4ResourceType.Patient).length, 1);
    });
  });

  group('export job sweep', () {
    Future<void> job(String id, String status, {DateTime? completedAt}) async {
      await db.createExportJob(
        jobId: id,
        status: status,
        requestUrl: r'http://x/$export',
        transactionTime: DateTime.now(),
        exportLevel: 'system',
      );
      if (completedAt != null || status != 'pending') {
        await db.updateExportJob(id, status: status, completedAt: completedAt);
      }
    }

    test('finishedExportJobsBefore: finished and older only', () async {
      final now = DateTime.now();
      await job(
        'old-done',
        'completed',
        completedAt: now.subtract(const Duration(hours: 30)),
      );
      await job(
        'old-error',
        'error',
        completedAt: now.subtract(const Duration(hours: 30)),
      );
      await job(
        'fresh-done',
        'completed',
        completedAt: now.subtract(const Duration(hours: 1)),
      );
      await job('running', 'in_progress');
      final expired = await db
          .finishedExportJobsBefore(now.subtract(const Duration(hours: 24)));
      expect(expired.map((j) => j.jobId).toSet(), {'old-done', 'old-error'});
      expect(
        await db.exportJobIds(),
        {'old-done', 'old-error', 'fresh-done', 'running'},
      );
    });

    test('failStaleExportJobs marks pending and in_progress, nothing else',
        () async {
      await job('p', 'pending');
      await job('r', 'in_progress');
      await job('d', 'completed', completedAt: DateTime.now());
      expect(await db.failStaleExportJobs('restarted'), 2);
      expect((await db.getExportJob('p'))!.status, 'error');
      expect((await db.getExportJob('r'))!.status, 'error');
      expect((await db.getExportJob('r'))!.completedAt, isNotNull);
      expect((await db.getExportJob('r'))!.errorJson, contains('restarted'));
      expect((await db.getExportJob('d'))!.status, 'completed');
      expect(await db.failStaleExportJobs('again'), 0);
    });
  });
}
