// Loads MIMIC-IV on FHIR NDJSON into a fhirant database and times it.
//
// Printing is the point: this is run from a terminal and read there.
// ignore_for_file: avoid_print
//
// Usage:
//   cd packages/fhirant_server
//   dart run tool/perf_load.dart <ndjson-dir> <db-path> [--limit N] [--batch N]
//
// Writes one row per batch to <db-path>.perf.tsv as it goes, flushed every
// time, so a run that is killed still leaves everything it measured. Then
// times the two things PLAN.md's performance item names: the dashboard's
// resource-count refresh, and a search.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    print('Usage: perf_load.dart <ndjson-dir> <db-path> [--limit N] '
        '[--batch N]');
    exit(64);
  }
  final dir = Directory(args[0]);
  final dbPath = args[1];
  final limit = _intArg(args, '--limit') ?? -1;
  final batchSize = _intArg(args, '--batch') ?? 500;

  // Appended synchronously, one row at a time: an IOSink with an in-flight
  // flush throws "StreamSink is bound to a stream" on the next write, and the
  // whole point of this file is that a killed run still leaves its numbers.
  final tsv = File('$dbPath.perf.tsv');
  tsv.parent.createSync(recursive: true);
  tsv.writeAsStringSync('phase\tdetail\tresources\tseconds\trate_per_s\n');

  void row(String phase, String detail, int count, double seconds) {
    final rate = seconds > 0 ? count / seconds : 0;
    tsv.writeAsStringSync(
      '$phase\t$detail\t$count\t${seconds.toStringAsFixed(2)}\t'
      '${rate.toStringAsFixed(0)}\n',
      mode: FileMode.append,
    );
    print('$phase $detail: $count in ${seconds.toStringAsFixed(2)}s '
        '(${rate.toStringAsFixed(0)}/s)');
  }

  final db = FhirAntDb(NativeDatabase(File('$dbPath/fhirant.sqlite')));

  // Two shapes are accepted: a directory of NDJSON, one resource per line
  // (MIMIC), and a directory of single-resource .json files (the fhir_r*
  // test assets, which matter because they carry 141 distinct resource types
  // against MIMIC's 11 — and the count refresh costs one query per type).
  final ndjson = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.ndjson'))
      .toList()
    ..sort((a, b) => a.lengthSync().compareTo(b.lengthSync()));
  final singles = ndjson.isNotEmpty
      ? <File>[]
      : (dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path)));
  final files = ndjson;

  var total = 0;
  final started = DateTime.now();

  for (final file in files) {
    if (limit >= 0 && total >= limit) break;
    final name = file.uri.pathSegments.last;
    final fileStart = DateTime.now();
    var inFile = 0;
    var batch = <fhir.Resource>[];

    Future<void> flushBatch() async {
      if (batch.isEmpty) return;
      final t = DateTime.now();
      await db.saveResources(batch);
      total += batch.length;
      inFile += batch.length;
      row(
        'load',
        name,
        batch.length,
        DateTime.now().difference(t).inMilliseconds / 1000,
      );
      batch = <fhir.Resource>[];
    }

    final lines = file.openRead().transform(utf8.decoder).transform(
          const LineSplitter(),
        );
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      if (limit >= 0 && total + batch.length >= limit) break;
      try {
        batch.add(fhir.Resource.fromJsonString(line));
      } catch (_) {
        // A line this build cannot parse is a fact about the data, not a
        // timing sample; count it and move on.
        continue;
      }
      if (batch.length >= batchSize) {
        await flushBatch();
      }
    }
    await flushBatch();
    row(
      'file',
      name,
      inFile,
      DateTime.now().difference(fileStart).inMilliseconds / 1000,
    );
  }

  if (singles.isNotEmpty) {
    var batch = <fhir.Resource>[];
    var skipped = 0;
    final singlesStart = DateTime.now();
    for (final file in singles) {
      if (limit >= 0 && total + batch.length >= limit) break;
      try {
        batch.add(fhir.Resource.fromJsonString(file.readAsStringSync()));
      } catch (_) {
        skipped++;
        continue;
      }
      if (batch.length >= batchSize) {
        final t = DateTime.now();
        await db.saveResources(batch);
        total += batch.length;
        row(
          'load',
          'json files',
          batch.length,
          DateTime.now().difference(t).inMilliseconds / 1000,
        );
        batch = <fhir.Resource>[];
      }
    }
    if (batch.isNotEmpty) {
      await db.saveResources(batch);
      total += batch.length;
    }
    row(
      'file',
      '${singles.length} json files, $skipped unparseable',
      total,
      DateTime.now().difference(singlesStart).inMilliseconds / 1000,
    );
  }

  row(
    'total-load',
    'all files',
    total,
    DateTime.now().difference(started).inMilliseconds / 1000,
  );

  // What PLAN.md's performance item actually names: the dashboard refresh is
  // one DISTINCT query plus one COUNT per type present, sequentially.
  final countStart = DateTime.now();
  final types = await db.getResourceTypes();
  var counted = 0;
  for (final type in types) {
    counted += await db.getResourceCount(type);
  }
  row(
    'count-refresh',
    '${types.length} types',
    counted,
    DateTime.now().difference(countStart).inMilliseconds / 1000,
  );

  // A search through the index, on a parameter every Observation carries.
  final searchStart = DateTime.now();
  final hits = await db.search(
    resourceType: fhir.R4ResourceType.Observation,
    searchParameters: const {
      'status': ['final'],
    },
    count: 20,
  );
  row(
    'search',
    'Observation?status=final (page of 20)',
    hits.length,
    DateTime.now().difference(searchStart).inMilliseconds / 1000,
  );

  final dbFile = File('$dbPath/fhirant.sqlite');
  print('database size: '
      '${(dbFile.lengthSync() / 1024 / 1024).toStringAsFixed(1)} MB');
  tsv.writeAsStringSync(
    'db-size-mb\t\t\t\t'
    '${(dbFile.lengthSync() / 1024 / 1024).toStringAsFixed(1)}\n',
    mode: FileMode.append,
  );
  await db.close();
}

int? _intArg(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i < 0 || i + 1 >= args.length) return null;
  return int.tryParse(args[i + 1]);
}
