// Compares a page of system `_history` as fhirant_db now reads it (the keys
// of the page merged from two order indexes, then those rows) against the
// query it replaced (every version sorted for each page), on a fhirant
// store: time per page at several offsets, and whether the rows are the
// same. Opening the store runs the schema-30 step that creates the indexes.
//
// Printing is the point: run from a terminal, read there.
// ignore_for_file: avoid_print
//
// Usage: dart run tool/sync_cost_2026-11-20/history_keyed.dart <db-dir>
import 'dart:io';

import 'package:drift/drift.dart' show QueryRow;
import 'package:fhirant_db/fhirant_db.dart';

Future<void> main(List<String> args) async {
  final db = FhirAntDb(
    openStoreFile(File('${args[0]}/fhirant.db'), 'default-development-key'),
  );
  final plan = await db
      .customSelect(
        'EXPLAIN QUERY PLAN SELECT rowid FROM resources '
        'ORDER BY last_updated DESC, version_id DESC, resource_type DESC, '
        'id DESC',
      )
      .get();
  print('order plan: ${plan.map((r) => r.read<String>('detail')).join('; ')}');

  // How many versions share a (last_updated, version_id) with another.
  final ties = await db
      .customSelect(
        'SELECT count(*) AS c FROM (SELECT last_updated, version_id, '
        'count(*) AS n FROM (SELECT last_updated, version_id '
        'FROM resources_history UNION ALL SELECT last_updated, version_id '
        'FROM resources) GROUP BY 1, 2 HAVING n > 1)',
      )
      .getSingle();
  print('(last_updated, version_id) groups shared by more than one version: '
      '${ties.read<int>('c')}');

  // The query before schema 30, with the same total order.
  String before(int offset) =>
      'SELECT rh.* FROM (SELECT resource_type, id, version_id, resource, '
      'last_updated, deleted FROM resources_history UNION ALL '
      'SELECT resource_type, id, version_id, resource, last_updated, '
      '0 AS deleted FROM resources) rh ORDER BY rh.last_updated DESC, '
      'rh.version_id DESC, rh.resource_type DESC, rh.id DESC '
      'LIMIT 500 OFFSET $offset';

  String key(String type, String id, String version) => '$type/$id/$version';
  String rowKey(QueryRow r) => key(
        r.read<String>('resource_type'),
        r.read<String>('id'),
        r.read<String>('version_id'),
      );

  for (final offset in [0, 500, 100000, 500000, 928500]) {
    final sw = Stopwatch()..start();
    final now = await db.getSystemHistory(count: 500, offset: offset);
    final nowMs = sw.elapsedMilliseconds;
    sw.reset();
    final old = await db.customSelect(before(offset)).get();
    final oldMs = sw.elapsedMilliseconds;
    final same = now.length == old.length &&
        [
          for (var i = 0; i < now.length; i++)
            key(now[i].resourceType, now[i].id, now[i].versionId) ==
                rowKey(old[i]),
        ].every((x) => x);
    print('offset $offset: now $nowMs ms, before $oldMs ms, '
        '${now.length} rows, same rows: $same');
  }
  await db.close();
}
