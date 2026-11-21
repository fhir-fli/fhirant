// Times a system `_history` page found by OFFSET (how fhirant_db pages
// now) against one found by the last row's sort key (keyset), at several
// depths of a fhirant store, and checks the rows are the same.
//
// Printing is the point: run from a terminal, read there.
// ignore_for_file: avoid_print
//
// Usage: dart run tool/sync_cost_2026-11-20/history_keyset.dart <db-dir>
import 'dart:io';

import 'package:drift/drift.dart' show QueryRow, Variable;
import 'package:fhirant_db/fhirant_db.dart';

Future<void> main(List<String> args) async {
  final db = FhirAntDb(
    openStoreFile(File('${args[0]}/fhirant.db'), 'default-development-key'),
  );
  final total = await db.countSystemHistory();
  print('versions: $total');

  String keys(String where, String limit) => 'SELECT last_updated AS lu, '
      'version_id AS vid, resource_type AS t, id AS i FROM ('
      'SELECT last_updated, version_id, resource_type, id '
      'FROM resources_history$where UNION ALL '
      'SELECT last_updated, version_id, resource_type, id '
      'FROM resources$where) '
      'ORDER BY 1 DESC, 2 DESC, 3 DESC, 4 DESC$limit';
  const after = ' WHERE (last_updated, version_id, resource_type, id) '
      '< (?, ?, ?, ?)';

  String key(QueryRow r) => '${r.read<String>('t')}/${r.read<String>('i')}/'
      '${r.read<String>('vid')}';

  for (final depth in [0, 500000, total ~/ 2, total - 1000]) {
    if (depth <= 0) continue;
    // The row just before the page: the keyset cursor a next link carries.
    final last = await db
        .customSelect(keys('', ' LIMIT 1 OFFSET ${depth - 1}'))
        .getSingle();
    final sw = Stopwatch()..start();
    final byOffset =
        await db.customSelect(keys('', ' LIMIT 500 OFFSET $depth')).get();
    final offsetMs = sw.elapsedMilliseconds;
    sw.reset();
    final byKey = await db.customSelect(
      keys(after, ' LIMIT 500'),
      variables: [
        for (var half = 0; half < 2; half++) ...[
          Variable.withInt(last.read<int>('lu')),
          Variable.withString(last.read<String>('vid')),
          Variable.withString(last.read<String>('t')),
          Variable.withString(last.read<String>('i')),
        ],
      ],
    ).get();
    final keyMs = sw.elapsedMilliseconds;
    final same = byOffset.map(key).join() == byKey.map(key).join();
    print('depth $depth: offset $offsetMs ms, keyset $keyMs ms, '
        'same rows: $same');
  }
  final plan = await db.customSelect(
    'EXPLAIN QUERY PLAN ${keys(after, ' LIMIT 500')}',
    variables: [
      for (var half = 0; half < 2; half++) ...[
        Variable.withInt(0),
        Variable.withString(''),
        Variable.withString(''),
        Variable.withString(''),
      ],
    ],
  ).get();
  print('keyset plan: ${plan.map((r) => r.read<String>('detail')).join('; ')}');
  await db.close();
}
