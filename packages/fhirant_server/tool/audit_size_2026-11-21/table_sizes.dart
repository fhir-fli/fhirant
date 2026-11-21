// Where a fhirant store's bytes are: pages per table and index (SQLite's
// dbstat), and how many of the resources and search-index rows belong to
// AuditEvent. Written to find why server B's store after a full $sync was
// 11.9 GB against server A's 6.4 GB with the same resources.
//
// Printing is the point: run from a terminal, read there.
// ignore_for_file: avoid_print
//
// Usage: dart run tool/audit_size_2026-11-21/table_sizes.dart <db-dir>
import 'dart:io';

import 'package:fhirant_db/fhirant_db.dart';

Future<void> main(List<String> args) async {
  final db = FhirAntDb(
    openStoreFile(File('${args[0]}/fhirant.db'), 'default-development-key'),
  );
  final rows = await db
      .customSelect(
        'SELECT name, sum(pgsize) AS bytes, count(*) AS pages FROM dbstat '
        'GROUP BY name ORDER BY bytes DESC',
      )
      .get();
  var total = 0;
  for (final r in rows) {
    total += r.read<int>('bytes');
  }
  print('total ${(total / 1e9).toStringAsFixed(2)} GB');
  for (final r in rows.take(40)) {
    final b = r.read<int>('bytes');
    print('${(b / 1e6).toStringAsFixed(0).padLeft(7)} MB  '
        '${r.read<String>('name')}');
  }
  final types = await db
      .customSelect(
        'SELECT resource_type, count(*) AS n, sum(length(resource)) AS bytes '
        'FROM resources GROUP BY 1 ORDER BY bytes DESC',
      )
      .get();
  for (final r in types.take(15)) {
    print('resources ${r.read<String>('resource_type')}: '
        '${r.read<int>('n')} rows, '
        '${(r.read<int>('bytes') / 1e6).toStringAsFixed(0)} MB of resource');
  }
  await db.close();
}
