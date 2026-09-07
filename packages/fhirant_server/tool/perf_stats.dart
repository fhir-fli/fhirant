// Shows the planner statistics a loaded fhirant database carries, and with
// `--analyze` runs ANALYZE and times it.
//
// Printing is the point: this is run from a terminal and read there.
// ignore_for_file: avoid_print
//
// Usage:
//   dart run tool/perf_stats.dart <db-path> [--analyze]
//
// Written 2026-09-06 when a freshly loaded 929k-resource database answered
// `status=final AND code` in 58s where the same query on the previous scratch
// database took 0.23s: the statistics had been gathered at create time, on
// empty tables.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: perf_stats.dart <db-path> [--analyze]');
    exit(64);
  }
  final db = FhirAntDb(NativeDatabase(File('${args[0]}/fhirant.sqlite')));

  Future<void> show(String label) async {
    print('== $label');
    final rows = await db
        .customSelect(
          'SELECT tbl, idx, stat FROM sqlite_stat1 '
          "WHERE tbl IN ('resources', 'token_search_parameters', "
          "'date_search_parameters', 'reference_search_parameters') "
          'ORDER BY tbl, idx',
        )
        .get();
    if (rows.isEmpty) print('  (no sqlite_stat1 rows)');
    for (final r in rows) {
      print(
        '  ${r.read<String>('tbl')}  ${r.read<String?>('idx') ?? '-'}  '
        '${r.read<String?>('stat') ?? '-'}',
      );
    }
    for (final table in ['resources', 'token_search_parameters']) {
      final c = await db.customSelect('SELECT COUNT(*) AS c FROM $table').get();
      print('  actual rows in $table: ${c.first.read<int>('c')}');
    }
  }

  final version = await db.customSelect('SELECT sqlite_version() AS v').get();
  print('sqlite ${version.first.read<String>('v')}');
  await show('before');
  if (args.contains('--analyze')) {
    final t = DateTime.now();
    await db.customStatement('ANALYZE');
    final seconds = DateTime.now().difference(t).inMilliseconds / 1000;
    print('ANALYZE took ${seconds.toStringAsFixed(2)}s');
    await show('after');
  }
  await db.close();
}
