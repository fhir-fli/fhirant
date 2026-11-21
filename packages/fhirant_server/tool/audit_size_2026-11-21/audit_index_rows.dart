// How many search-index rows AuditEvent has in a fhirant store, by table
// and search parameter, against every other type's: the follow-up to
// table_sizes.dart, which found server B's extra 5.5 GB in the search
// index tables after a full $sync wrote 939,083 AuditEvents.
//
// Printing is the point: run from a terminal, read there.
// ignore_for_file: avoid_print
//
// Usage: dart run tool/audit_size_2026-11-21/audit_index_rows.dart <db-dir>
import 'dart:io';

import 'package:drift/drift.dart' show QueryRow, Variable;
import 'package:fhirant_db/fhirant_db.dart';

Future<void> main(List<String> args) async {
  final db = FhirAntDb(
    openStoreFile(File('${args[0]}/fhirant.db'), 'default-development-key'),
  );
  final cols = await db
      .customSelect(
        'SELECT sql FROM sqlite_schema '
        "WHERE name = 'token_search_parameters'",
      )
      .getSingle();
  print(cols.read<String>('sql'));
  const tables = [
    'token',
    'reference',
    'date',
    'string',
    'uri',
    'quantity',
    'composite',
  ];
  for (final t in tables) {
    final rows = await db.customSelect(
      'SELECT resource_type = ? AS audit, search_name, count(*) AS n '
      'FROM ${t}_search_parameters GROUP BY 1, 2 ORDER BY 1 DESC, 3 DESC',
      variables: [const Variable<String>('AuditEvent')],
    ).get();
    for (final r in rows) {
      if (r.read<int>('audit') != 1) continue;
      print('$t AuditEvent ${r.read<String>('search_name')}: '
          '${r.read<int>('n')}');
    }
    final all = await db.customSelect(
      'SELECT resource_type = ? AS audit, count(*) AS n '
      'FROM ${t}_search_parameters GROUP BY 1',
      variables: [const Variable<String>('AuditEvent')],
    ).get();
    String side(QueryRow r) => r.read<int>('audit') == 1 ? 'audit' : 'other';
    final totals = [for (final r in all) '${side(r)}=${r.read<int>('n')}'];
    print('$t totals: ${totals.join(' ')}');
  }
  await db.close();
}
