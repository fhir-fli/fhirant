// Review 2026-09-06: does a covering composite index change the numbers the
// parked performance items rest on? Run against a loaded MIMIC database:
//
//   dart run tool/review_2026-09-06/index_ab.dart <db-dir>
//
// Everything is written to <db-dir>/index_ab.tsv as it is measured. Each
// query runs twice, interleaved with its alternative, and the database is
// ANALYZEd first so the planner has real statistics (see perf_stats.dart).
//
// Printing is the point: this is run from a terminal and read there.
// ignore_for_file: avoid_print, lines_longer_than_80_chars, prefer_single_quotes, require_trailing_commas
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: index_ab.dart <db-dir>');
    exit(64);
  }
  final dir = args[0];
  final db = FhirAntDb(NativeDatabase(File('$dir/fhirant.sqlite')));
  final tsv = File('$dir/index_ab.tsv')
    ..writeAsStringSync('step\tlabel\tms\trows\tnote\n');
  void row(String step, String label, int ms, int rows, [String note = '']) {
    tsv.writeAsStringSync(
      '$step\t$label\t$ms\t$rows\t$note\n',
      mode: FileMode.append,
    );
    print(
        '[$step] $label: ${(ms / 1000).toStringAsFixed(2)}s ($rows rows) $note');
  }

  Future<int> timed(
    String step,
    String label,
    Future<int> Function() body, [
    String note = '',
  ]) async {
    final sw = Stopwatch()..start();
    final n = await body();
    sw.stop();
    row(step, label, sw.elapsedMilliseconds, n, note);
    return n;
  }

  Future<List<String>> plan(String sql) async =>
      (await db.customSelect('EXPLAIN QUERY PLAN $sql').get())
          .map((r) => r.read<String>('detail'))
          .toList();

  Future<int> sqlCount(String sql) async =>
      (await db.customSelect(sql).get()).length;

  // 0. Statistics, as the server would have them.
  await timed('0-analyze', 'ANALYZE', () async {
    await db.customStatement('ANALYZE');
    return 0;
  });

  // The patient with the most Observations, and a small one, from the index.
  final top = await db
      .customSelect(
        "SELECT reference_id_part AS pid, count(*) AS c FROM reference_search_parameters "
        "WHERE resource_type = 'Observation' AND search_name = 'subject' "
        "GROUP BY pid ORDER BY c DESC LIMIT 1",
      )
      .getSingle();
  final small = await db
      .customSelect(
        "SELECT reference_id_part AS pid, count(*) AS c FROM reference_search_parameters "
        "WHERE resource_type = 'Observation' AND search_name = 'subject' "
        "GROUP BY pid HAVING c BETWEEN 500 AND 1500 ORDER BY c LIMIT 1",
      )
      .getSingle();
  final bigPatient = top.read<String>('pid');
  final bigCount = top.read<int>('c');
  final smallPatient = small.read<String>('pid');
  final smallCount = small.read<int>('c');
  row('0-patients', 'big patient $bigPatient', 0, bigCount);
  row('0-patients', 'small patient $smallPatient', 0, smallCount);

  // 1. The DAO as it stands: status=final sorted by -date, big patient sorted,
  //    small patient sorted, string family starts-with, plain type page.
  Future<int> daoSorted(Map<String, List<String>> params) async =>
      (await db.search(
        resourceType: fhir.R4ResourceType.Observation,
        searchParameters: params,
        sort: ['-date'],
        count: 20,
      ))
          .length;

  // 2. The alternative: a covering index on the sort column, walked in order,
  //    with the filter as a correlated EXISTS on the other table's key.
  const cover =
      'CREATE INDEX IF NOT EXISTS idx_review_date_cover ON date_search_parameters '
      '(resource_type, search_name, date_value, id)';
  const tokenCover =
      'CREATE INDEX IF NOT EXISTS idx_review_token_cover ON token_search_parameters '
      '(resource_type, search_name, token_value, id)';
  const refCover =
      'CREATE INDEX IF NOT EXISTS idx_review_ref_cover ON reference_search_parameters '
      '(resource_type, search_name, reference_resource_type, reference_id_part, id)';
  const stringCover =
      'CREATE INDEX IF NOT EXISTS idx_review_string_cover ON string_search_parameters '
      '(resource_type, search_name, string_value, id)';
  const lastUpdatedIdx =
      'CREATE INDEX IF NOT EXISTS idx_review_resources_lu ON resources '
      '(resource_type, last_updated)';

  String walkStatus() =>
      "SELECT d.id FROM date_search_parameters d WHERE d.resource_type = 'Observation' AND d.search_name = 'date' "
      "AND EXISTS (SELECT 1 FROM token_search_parameters t WHERE t.resource_type = 'Observation' AND t.id = d.id "
      "AND t.search_name = 'status' AND t.token_value = 'final') ORDER BY d.date_value DESC LIMIT 20";
  String walkPatient(String pid) =>
      "SELECT d.id FROM date_search_parameters d WHERE d.resource_type = 'Observation' AND d.search_name = 'date' "
      "AND EXISTS (SELECT 1 FROM reference_search_parameters r WHERE r.resource_type = 'Observation' AND r.id = d.id "
      "AND r.search_name = 'subject' AND r.reference_resource_type = 'Patient' AND r.reference_id_part = '$pid') "
      'ORDER BY d.date_value DESC LIMIT 20';
  // The filtered set sorted (what the DAO's grouped join does), hand-written
  // with search_name only, for the small patient where the set is small.
  String sortedSet(String pid) =>
      "SELECT r.id FROM reference_search_parameters r LEFT JOIN date_search_parameters d ON d.resource_type = 'Observation' "
      "AND d.search_name = 'date' AND d.id = r.id WHERE r.resource_type = 'Observation' AND r.search_name = 'subject' "
      "AND r.reference_resource_type = 'Patient' AND r.reference_id_part = '$pid' GROUP BY r.id ORDER BY max(d.date_value) DESC NULLS LAST, r.id LIMIT 20";
  const stringLike =
      "SELECT DISTINCT id FROM string_search_parameters WHERE resource_type = 'Patient' "
      "AND (search_name = 'family' OR search_path LIKE 'Patient.family' OR search_path LIKE 'Patient.%.family') "
      "AND string_value LIKE 'a%'";
  const stringRange =
      "SELECT DISTINCT id FROM string_search_parameters WHERE resource_type = 'Patient' AND search_name = 'family' "
      "AND string_value >= 'a' AND string_value < 'b'";
  const tokenDao =
      "SELECT DISTINCT id FROM token_search_parameters WHERE resource_type = 'Observation' "
      "AND (search_name = 'code' OR search_path LIKE 'Observation.code' OR search_path LIKE 'Observation.%.code') "
      "AND token_value = '227969' ORDER BY id LIMIT 20";
  const tokenPlain =
      "SELECT DISTINCT id FROM token_search_parameters WHERE resource_type = 'Observation' "
      "AND search_name = 'code' AND token_value = '227969' ORDER BY id LIMIT 20";
  const typePage =
      "SELECT id FROM resources WHERE resource_type = 'Observation' ORDER BY last_updated DESC LIMIT 20";
  const lastUpdatedSearch =
      "SELECT id FROM resources WHERE resource_type = 'Observation' AND last_updated >= 4000000000000 LIMIT 20";

  for (final round in [1, 2]) {
    await timed(
        '1-dao-r$round',
        'DAO status=final -date',
        () => daoSorted({
              'status': ['final']
            }));
    await timed(
        '1-dao-r$round',
        'DAO subject=big -date',
        () => daoSorted({
              'subject': ['Patient/$bigPatient']
            }));
    await timed(
        '1-dao-r$round',
        'DAO subject=small -date',
        () => daoSorted({
              'subject': ['Patient/$smallPatient']
            }));
    await timed('1-sql-r$round', 'SQL walk status=final (no cover index)',
        () => sqlCount(walkStatus()));
    await timed('1-sql-r$round', 'SQL string LIKE (as DAO)',
        () => sqlCount(stringLike));
    await timed(
        '1-sql-r$round', 'SQL string range', () => sqlCount(stringRange));
    await timed('1-sql-r$round', 'SQL token (as DAO, with LIKE ORs)',
        () => sqlCount(tokenDao));
    await timed('1-sql-r$round', 'SQL token (search_name only)',
        () => sqlCount(tokenPlain));
    await timed('1-sql-r$round', 'SQL type page ORDER BY last_updated',
        () => sqlCount(typePage));
    await timed('1-sql-r$round', 'SQL _lastUpdated >=',
        () => sqlCount(lastUpdatedSearch));
  }
  row('1-plan', 'walk status (no cover)', 0, 0,
      (await plan(walkStatus())).join(' | '));
  row('1-plan', 'string LIKE (as DAO)', 0, 0,
      (await plan(stringLike)).join(' | '));
  row('1-plan', 'token (as DAO)', 0, 0, (await plan(tokenDao)).join(' | '));
  row('1-plan', 'type page', 0, 0, (await plan(typePage)).join(' | '));

  // Sizes before.
  final sizeBefore = File('$dir/fhirant.sqlite').lengthSync();
  row('2-size', 'db bytes before covering indexes', 0, 0, '$sizeBefore');

  for (final (name, ddl) in [
    ('date cover', cover),
    ('token cover', tokenCover),
    ('reference cover', refCover),
    ('string cover', stringCover),
    ('resources (type,last_updated)', lastUpdatedIdx),
  ]) {
    await timed('2-create', 'CREATE INDEX $name', () async {
      await db.customStatement(ddl);
      return 0;
    });
  }
  await timed('2-analyze', 'ANALYZE after', () async {
    await db.customStatement('ANALYZE');
    return 0;
  });
  final sizeAfter = File('$dir/fhirant.sqlite').lengthSync();
  row('2-size', 'db bytes after covering indexes', 0, 0,
      '$sizeAfter (+${((sizeAfter - sizeBefore) / 1024 / 1024).toStringAsFixed(0)} MB)');

  for (final round in [1, 2]) {
    await timed(
        '3-dao-r$round',
        'DAO status=final -date (indexes present)',
        () => daoSorted({
              'status': ['final']
            }));
    await timed(
        '3-dao-r$round',
        'DAO subject=big -date (indexes present)',
        () => daoSorted({
              'subject': ['Patient/$bigPatient']
            }));
    await timed(
        '3-dao-r$round',
        'DAO subject=small -date (indexes present)',
        () => daoSorted({
              'subject': ['Patient/$smallPatient']
            }));
    await timed('3-sql-r$round', 'SQL walk status=final (cover)',
        () => sqlCount(walkStatus()));
    await timed('3-sql-r$round', 'SQL walk subject=big (cover)',
        () => sqlCount(walkPatient(bigPatient)));
    await timed('3-sql-r$round', 'SQL walk subject=small (cover)',
        () => sqlCount(walkPatient(smallPatient)));
    await timed('3-sql-r$round', 'SQL sorted-set subject=small (cover)',
        () => sqlCount(sortedSet(smallPatient)));
    await timed('3-sql-r$round', 'SQL sorted-set subject=big (cover)',
        () => sqlCount(sortedSet(bigPatient)));
    await timed('3-sql-r$round', 'SQL string LIKE (as DAO, cover present)',
        () => sqlCount(stringLike));
    await timed('3-sql-r$round', 'SQL string range (cover)',
        () => sqlCount(stringRange));
    await timed('3-sql-r$round', 'SQL token (as DAO, cover present)',
        () => sqlCount(tokenDao));
    await timed('3-sql-r$round', 'SQL token (search_name only, cover)',
        () => sqlCount(tokenPlain));
    await timed('3-sql-r$round', 'SQL type page ORDER BY last_updated (index)',
        () => sqlCount(typePage));
    await timed('3-sql-r$round', 'SQL _lastUpdated >= (index)',
        () => sqlCount(lastUpdatedSearch));
  }
  row('3-plan', 'walk status (cover)', 0, 0,
      (await plan(walkStatus())).join(' | '));
  row('3-plan', 'walk subject=big (cover)', 0, 0,
      (await plan(walkPatient(bigPatient))).join(' | '));
  row('3-plan', 'string range (cover)', 0, 0,
      (await plan(stringRange)).join(' | '));
  row('3-plan', 'string LIKE as DAO (cover present)', 0, 0,
      (await plan(stringLike)).join(' | '));
  row('3-plan', 'token search_name only (cover)', 0, 0,
      (await plan(tokenPlain)).join(' | '));
  row('3-plan', 'type page (index)', 0, 0, (await plan(typePage)).join(' | '));

  // Storage: how big each table and index is, if dbstat is available.
  try {
    final sizes = await db
        .customSelect(
          'SELECT name, SUM(pgsize) AS bytes FROM dbstat GROUP BY name ORDER BY bytes DESC LIMIT 40',
        )
        .get();
    for (final s in sizes) {
      row('4-dbstat', s.read<String>('name'), 0, 0, '${s.read<int>('bytes')}');
    }
  } catch (e) {
    row('4-dbstat', 'dbstat unavailable', 0, 0, '$e');
  }

  // Leave the database as it was found.
  for (final name in [
    'idx_review_date_cover',
    'idx_review_token_cover',
    'idx_review_ref_cover',
    'idx_review_string_cover',
    'idx_review_resources_lu',
  ]) {
    await db.customStatement('DROP INDEX IF EXISTS $name');
  }
  await db.close();
  print('done; results in $dir/index_ab.tsv');
}
