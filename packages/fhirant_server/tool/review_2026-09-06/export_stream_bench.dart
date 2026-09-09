// REVIEW-2026-09-06 finding 34: `$export` of one type, the old way (whole
// type into a List<Resource>, decode, re-encode) against the new way
// (FhirAntDb.exportJson, stored JSON streamed a page at a time).
//
//   dart run tool/review_2026-09-06/export_stream_bench.dart <dir> <tsv> <Type> old|new
//
// <dir> holds fhirant.sqlite (the MIMIC copy). Writes one row per step to
// <tsv> as it goes: wall ms, resources, file MB, RSS MB at the end, and the
// longest gap the event loop saw (a 5 ms timer's lateness), which is what a
// request on the same isolate would wait.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhir_r4_bulk/fhir_r4_bulk.dart';
import 'package:fhirant_db/fhirant_db.dart';

Future<void> main(List<String> args) async {
  final dir = args[0];
  final tsv = File(args[1]);
  final type = fhir.R4ResourceType.fromString(args[2])!;
  final mode = args[3];
  if (!tsv.existsSync()) {
    tsv.writeAsStringSync(
      'mode\ttype\tms\tresources\tfile_mb\trss_mb\tmax_stall_ms\trss_open_mb\n',
    );
  }
  final db = FhirAntDb(NativeDatabase(File('$dir/fhirant.sqlite')));
  await db.initialize();
  // Opening the 7 GB store through FhirAntDb costs RSS on its own (the
  // schema check and the first reads); the export's share is the difference.
  final rssOpen = ProcessInfo.currentRss ~/ (1024 * 1024);
  stdout.writeln('rss after open: ${rssOpen}MB');
  final out = '$dir/export_bench_${args[2]}_$mode.ndjson';

  var maxStall = 0;
  var expected = DateTime.now().add(const Duration(milliseconds: 5));
  final ticker = Timer.periodic(const Duration(milliseconds: 5), (_) {
    final late = DateTime.now().difference(expected).inMilliseconds;
    if (late > maxStall) maxStall = late;
    expected = DateTime.now().add(const Duration(milliseconds: 5));
  });
  final progress = Timer.periodic(const Duration(seconds: 10), (_) {
    final f = File(out);
    stdout.writeln(
      'progress: rss=${ProcessInfo.currentRss ~/ (1024 * 1024)}MB '
      'file=${f.existsSync() ? f.lengthSync() ~/ (1024 * 1024) : 0}MB '
      'stall=${maxStall}ms',
    );
  });

  final sw = Stopwatch()..start();
  int count;
  if (mode == 'old') {
    // What export_handler.dart did before 2026-09-08. The method is kept,
    // deprecated, for this bench alone.
    // ignore: deprecated_member_use
    final resources = await db.getResourcesByTypeSince(type);
    final file = File(out);
    final sink = file.openWrite();
    for (final r in resources) {
      sink.writeln(jsonEncode(r.toJson()));
    }
    await sink.flush();
    await sink.close();
    count = resources.length;
  } else {
    final file = File(out);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    try {
      count = await NdjsonStream.write(
        db.exportJson(type),
        sink,
        flush: sink.flush,
      );
    } finally {
      await sink.close();
    }
  }
  sw.stop();
  ticker.cancel();
  progress.cancel();
  final rss = ProcessInfo.currentRss ~/ (1024 * 1024);
  final mb = File(out).lengthSync() ~/ (1024 * 1024);
  final row = '$mode\t${args[2]}\t${sw.elapsedMilliseconds}\t$count\t$mb\t'
      '$rss\t$maxStall\t$rssOpen\n';
  tsv.writeAsStringSync(row, mode: FileMode.append);
  stdout.write(row);
  await File(out).delete();
  await db.close();
}
