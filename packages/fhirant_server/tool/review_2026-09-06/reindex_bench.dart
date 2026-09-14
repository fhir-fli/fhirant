// What a full search-index rebuild ($reindex) costs on the MIMIC sample, and
// what a save meets while it runs: the rebuild timed on a file-backed store
// holding every MIMIC ndjson line, with one saveResource attempted every
// 500 ms during it (latency, or the error). Decides the shape of fhirant's
// $reindex (synchronous answer or async job) from a number rather than a
// guess. Rows are appended and flushed as they are measured.
//
//   dart run tool/review_2026-09-06/reindex_bench.dart \
//     tool/review_2026-09-06/reindex_bench.tsv <label>
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';

Future<void> main(List<String> args) async {
  final tsv = File(args[0]);
  final label = args[1];
  if (!tsv.existsSync()) {
    tsv.writeAsStringSync('label\tphase\tresources\tms\tnote\n');
  }
  void row(String phase, int resources, int ms, [String note = '']) {
    final line = '$label\t$phase\t$resources\t$ms\t$note\n';
    tsv.writeAsStringSync(line, mode: FileMode.append, flush: true);
    stdout.write(line);
  }

  final dir = Directory.systemTemp.createTempSync('fhirant_reindex_');
  final db = FhirAntDb(NativeDatabase(File('${dir.path}/fhirant.sqlite')));
  await db.initialize();

  // Load every MIMIC line, 500 a batch.
  var total = 0;
  final loadSw = Stopwatch()..start();
  final files = Directory('assets/mimic')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.ndjson'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final batch = <fhir.Resource>[];
    for (final line in file.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      batch.add(
        fhir.Resource.fromJson(jsonDecode(line) as Map<String, dynamic>),
      );
      if (batch.length == 500) {
        await db.saveResources(batch);
        total += batch.length;
        batch.clear();
      }
    }
    if (batch.isNotEmpty) {
      await db.saveResources(batch);
      total += batch.length;
    }
    stdout.writeln('loaded $total after ${file.uri.pathSegments.last}');
  }
  row('load', total, loadSw.elapsedMilliseconds);

  // Saves during the rebuild, one every 500 ms, each timed or failed.
  var saving = true;
  var saveCount = 0;
  var saveErrors = 0;
  var saveMaxMs = 0;
  var saveSumMs = 0;
  Future<void> saver() async {
    var i = 0;
    while (saving) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final sw = Stopwatch()..start();
      try {
        await db.saveResource(
          fhir.Patient.fromJson({
            'resourceType': 'Patient',
            'id': 'during-${i++}',
            'name': [
              {'family': 'During'},
            ],
          }),
        );
        saveCount++;
        saveSumMs += sw.elapsedMilliseconds;
        if (sw.elapsedMilliseconds > saveMaxMs) {
          saveMaxMs = sw.elapsedMilliseconds;
        }
      } catch (e) {
        saveErrors++;
        row('save_during_error', 0, sw.elapsedMilliseconds, '$e');
      }
    }
  }

  final saverDone = saver();
  final rebuildSw = Stopwatch()..start();
  await db.rebuildSearchIndex();
  rebuildSw.stop();
  saving = false;
  await saverDone;
  row('rebuild', total, rebuildSw.elapsedMilliseconds);
  row(
    'saves_during',
    saveCount,
    saveCount == 0 ? 0 : saveSumMs ~/ saveCount,
    'mean ms; max $saveMaxMs ms; errors $saveErrors',
  );
  final count = (await db
          .customSelect('SELECT count(*) AS n FROM token_search_parameters')
          .getSingle())
      .read<int>('n');
  row('token_rows_after', count, 0);
  await db.close();
  stdout.writeln('store: ${dir.path}');
}
