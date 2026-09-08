// Review 2026-09-06, §8 step 3 (the schema pass): the same searches through
// the production path (FhirAntDb.search) before and after the schema change,
// on the loaded MIMIC database.
//
//   dart run tool/review_2026-09-06/schema10_ab.dart <db-dir> <label>
//
// Run once with the package as committed before the change (label
// `before`) and once with the change (label `after`); the second run's open
// includes the upgrade, which is timed. Every row is appended to
// <db-dir>/schema10_ab.tsv as it is measured. Each query runs in two
// interleaved rounds.
// ignore_for_file: avoid_print, lines_longer_than_80_chars, prefer_single_quotes, require_trailing_commas
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    print('Usage: schema10_ab.dart <db-dir> <label>');
    exit(64);
  }
  final dir = args[0];
  final label = args[1];
  final tsv = File('$dir/schema10_ab.tsv');
  if (!tsv.existsSync()) {
    tsv.writeAsStringSync('label\tstep\tquery\tms\trows\tnote\n');
  }
  void row(String step, String query, int ms, int rows, [String note = '']) {
    tsv.writeAsStringSync('$label\t$step\t$query\t$ms\t$rows\t$note\n',
        mode: FileMode.append);
    print('[$label $step] $query: ${(ms / 1000).toStringAsFixed(3)}s ($rows) $note');
  }

  Future<int> timed(String step, String query, Future<int> Function() body,
      [String note = '']) async {
    final sw = Stopwatch()..start();
    final n = await body();
    sw.stop();
    row(step, query, sw.elapsedMilliseconds, n, note);
    return n;
  }

  final db = FhirAntDb(NativeDatabase(File('$dir/fhirant.sqlite')));

  // 0. Open: on a database behind the package's schema this is the upgrade.
  final version = await timed('0-open', 'open (upgrade if behind)', () async {
    final v = await db.customSelect('PRAGMA user_version').getSingle();
    return v.data.values.first as int;
  });
  row('0-open', 'user_version', 0, version);
  // The package's full index set, IF NOT EXISTS: restores anything an
  // experiment dropped (index_trim_ab.dart) without touching the rest.
  await timed('0-open', 'createValueIndexes (IF NOT EXISTS)', () async {
    await db.createValueIndexes();
    return 0;
  });
  row('0-open', 'db bytes', 0, 0, '${File('$dir/fhirant.sqlite').lengthSync()}');
  await timed('0-analyze', 'ANALYZE', () async {
    await db.customStatement('ANALYZE');
    return 0;
  });

  final top = await db
      .customSelect(
          "SELECT reference_id_part AS pid, count(*) AS c FROM reference_search_parameters "
          "WHERE resource_type = 'Observation' AND search_name = 'subject' "
          "GROUP BY pid ORDER BY c DESC LIMIT 1")
      .getSingle();
  final small = await db
      .customSelect(
          "SELECT reference_id_part AS pid, count(*) AS c FROM reference_search_parameters "
          "WHERE resource_type = 'Observation' AND search_name = 'subject' "
          "GROUP BY pid HAVING c BETWEEN 500 AND 1500 ORDER BY c LIMIT 1")
      .getSingle();
  final big = top.read<String>('pid');
  final smallPid = small.read<String>('pid');
  row('0-patients', 'big patient $big', 0, top.read<int>('c'));
  row('0-patients', 'small patient $smallPid', 0, small.read<int>('c'));
  final system = (await db
          .customSelect(
              "SELECT token_system AS s FROM token_search_parameters WHERE resource_type = 'Observation' "
              "AND search_name = 'code' AND token_value = '227969' LIMIT 1")
          .getSingleOrNull())
      ?.read<String?>('s');
  row('0-patients', 'system of code 227969', 0, 0, '$system');

  Future<int> search(Map<String, List<String>> params,
          {List<String>? sort, CompartmentScope? compartment, String type = 'Observation'}) async =>
      (await db.search(
        resourceType: fhir.R4ResourceType.fromString(type)!,
        searchParameters: params,
        sort: sort,
        count: 20,
        compartment: compartment,
      ))
          .length;

  final queries = <(String, Future<int> Function())>[
    ('status=final&_sort=-date', () => search({'status': ['final']}, sort: ['-date'])),
    ('subject=big&_sort=-date', () => search({'subject': ['Patient/$big']}, sort: ['-date'])),
    ('subject=small&_sort=-date', () => search({'subject': ['Patient/$smallPid']}, sort: ['-date'])),
    ('subject=big', () => search({'subject': ['Patient/$big']})),
    ('Patient/big compartment Observation', () => search({}, compartment: CompartmentScope('Patient', big))),
    ('code=227969', () => search({'code': ['227969']})),
    ('code=system|227969', () => search({'code': ['$system|227969']})),
    ('code=system| (system only)', () => search({'code': ['$system|']})),
    ('status=final&code=227969', () => search({'status': ['final'], 'code': ['227969']})),
    ('code:text=glucose (documented scan)', () => search({'code:text': ['glucose']})),
    ('no parameters (type page)', () => search({})),
    ('_lastUpdated=ge2000-01-01 (all)', () => search({'_lastUpdated': ['ge2000-01-01']})),
    ('_lastUpdated=ge2999-01-01 (none)', () => search({'_lastUpdated': ['ge2999-01-01']})),
    ('date=ge2150-01-01', () => search({'date': ['ge2150-01-01']})),
    ('value-quantity=gt100', () => search({'value-quantity': ['gt100']})),
    ('Patient?family=a (string starts-with)', () => search({'family': ['a']}, type: 'Patient')),
    ('Patient?family:exact=Smith', () => search({'family:exact': ['Smith']}, type: 'Patient')),
    ('_id=<big patient>', () => search({'_id': [big]}, type: 'Patient')),
  ];
  for (final round in [1, 2]) {
    for (final (name, body) in queries) {
      try {
        await timed('1-r$round', name, body);
      } catch (e) {
        row('1-r$round', name, -1, 0, 'ERROR $e');
      }
    }
    await timed('1-r$round', 'searchCount subject=big', () => db.searchCount(
        resourceType: fhir.R4ResourceType.Observation,
        searchParameters: {'subject': ['Patient/$big']}));
  }

  // Plans of the shapes the DAO writes, as hand SQL, for the record.
  Future<String> plan(String sql) async =>
      (await db.customSelect('EXPLAIN QUERY PLAN $sql').get())
          .map((r) => r.read<String>('detail'))
          .join(' | ');
  final hasPath = (await db.customSelect("PRAGMA table_info(token_search_parameters)").get())
      .any((r) => r.read<String>('name') == 'search_path');
  final nameOnly = !hasPath;
  String path(String t, String name) => nameOnly
      ? "search_name = '$name'"
      : "(search_name = '$name' OR search_path LIKE '$t.$name' OR search_path LIKE '$t.%.$name')";
  for (final (name, sql) in [
    ('token code', "SELECT DISTINCT id FROM token_search_parameters WHERE resource_type = 'Observation' AND ${path('Observation', 'code')} AND token_value = '227969' ORDER BY id LIMIT 20"),
    ('reference subject', "SELECT DISTINCT id FROM reference_search_parameters WHERE resource_type = 'Observation' AND ${path('Observation', 'subject')} AND reference_resource_type = 'Patient' AND reference_id_part = '$big'"),
    ('date range', "SELECT DISTINCT id FROM date_search_parameters WHERE resource_type = 'Observation' AND ${path('Observation', 'date')} AND date_value >= 5000000000 LIMIT 20"),
    ('string starts-with LIKE', "SELECT DISTINCT id FROM string_search_parameters WHERE resource_type = 'Patient' AND ${path('Patient', 'family')} AND string_value LIKE 'a%'"),
    ('string starts-with range', "SELECT DISTINCT id FROM string_search_parameters WHERE resource_type = 'Patient' AND ${path('Patient', 'family')} AND string_value >= 'a' AND string_value < 'b'"),
    ('type page', "SELECT id FROM resources WHERE resource_type = 'Observation' ORDER BY last_updated DESC LIMIT 20"),
    ('last_updated range', "SELECT id FROM resources WHERE resource_type = 'Observation' AND last_updated >= 4000000000000 LIMIT 20"),
    ('owner delete', "DELETE FROM token_search_parameters WHERE resource_type = 'Observation' AND id = 'x'"),
  ]) {
    try {
      row('2-plan', name, 0, 0, await plan(sql));
    } catch (e) {
      row('2-plan', name, 0, 0, 'ERROR $e');
    }
  }

  row('3-size', 'db bytes', 0, 0, '${File('$dir/fhirant.sqlite').lengthSync()}');
  try {
    final sizes = await db
        .customSelect('SELECT name, SUM(pgsize) AS bytes FROM dbstat GROUP BY name ORDER BY bytes DESC LIMIT 60')
        .get();
    for (final s in sizes) {
      row('3-dbstat', s.read<String>('name'), 0, 0, '${s.read<int>('bytes')}');
    }
  } catch (e) {
    row('3-dbstat', 'dbstat unavailable', 0, 0, '$e');
  }
  await db.close();
  print('done; results in ${tsv.path}');
}
