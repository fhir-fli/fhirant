// Schema 10 follow-up: two covering indexes on long strings cost 437 MB
// (token_system) and 334 MB (reference_value) on the MIMIC load. This drops
// them and times the searches they served, through FhirAntDb.search, so
// the decision to keep or drop them rests on a number.
//
//   dart run tool/review_2026-09-06/index_trim_ab.dart <db-dir>
//
// Appends to <db-dir>/index_trim_ab.tsv as it goes. The indexes are left
// dropped: recreate with FhirDb.createValueIndexes (they are IF NOT EXISTS)
// if the decision goes the other way.
// ignore_for_file: avoid_print, lines_longer_than_80_chars
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';

Future<void> main(List<String> args) async {
  final dir = args[0];
  final tsv = File('$dir/index_trim_ab.tsv');
  if (!tsv.existsSync()) tsv.writeAsStringSync('phase\tquery\tms\trows\tnote\n');
  void row(String phase, String q, int ms, int rows, [String note = '']) {
    tsv.writeAsStringSync('$phase\t$q\t$ms\t$rows\t$note\n', mode: FileMode.append);
    print('[$phase] $q: ${ms}ms ($rows) $note');
  }
  Future<void> timed(String phase, String q, Future<int> Function() body) async {
    final sw = Stopwatch()..start();
    final n = await body();
    row(phase, q, sw.elapsedMilliseconds, n);
  }
  final db = FhirAntDb(NativeDatabase(File('$dir/fhirant.sqlite')));
  await db.customSelect('SELECT 1').get();
  final system = (await db.customSelect("SELECT token_system AS s FROM token_search_parameters WHERE resource_type = 'Observation' AND search_name = 'code' AND token_value = '227969' LIMIT 1").getSingle()).read<String?>('s');
  final rareSystem = (await db.customSelect("SELECT token_system AS s, count(*) AS c FROM token_search_parameters WHERE resource_type = 'Observation' AND search_name = 'category' GROUP BY s ORDER BY c LIMIT 1").getSingleOrNull())?.read<String?>('s');
  row('0', 'systems', 0, 0, 'code: $system; rare category system: $rareSystem');
  Future<int> search(Map<String, List<String>> p) async => (await db.search(resourceType: fhir.R4ResourceType.Observation, searchParameters: p, count: 20)).length;
  Future<String> plan(String sql) async => (await db.customSelect('EXPLAIN QUERY PLAN $sql').get()).map((r) => r.read<String>('detail')).join(' | ');
  const absRef = "SELECT DISTINCT id FROM reference_search_parameters WHERE resource_type = 'Observation' AND search_name = 'subject' AND reference_value = 'http://example.org/fhir/Patient/nobody' LIMIT 20";
  const belowRef = "SELECT DISTINCT id FROM reference_search_parameters WHERE resource_type = 'Observation' AND search_name = 'subject' AND (reference_value = 'http://example.org/fhir/Patient/nobody' OR substr(reference_value, 1, 38) = 'http://example.org/fhir/Patient/nobody|') LIMIT 20";
  Future<void> round(String phase) async {
    for (var i = 1; i <= 2; i++) {
      await timed('$phase-r$i', 'code=system| (system only, the common system)', () => search({'code': ['$system|']}));
      await timed('$phase-r$i', 'code=system|227969', () => search({'code': ['$system|227969']}));
      if (rareSystem != null) {
        await timed('$phase-r$i', 'category=rareSystem|', () => search({'category': ['$rareSystem|']}));
      }
      await timed('$phase-r$i', 'category=http://nobody.example|', () => search({'category': ['http://nobody.example|']}));
      await timed('$phase-r$i', 'SQL absolute reference (no match)', () async => (await db.customSelect(absRef).get()).length);
      await timed('$phase-r$i', 'SQL reference :below (no match)', () async => (await db.customSelect(belowRef).get()).length);
    }
    row('$phase-plan', 'absolute reference', 0, 0, await plan(absRef));
    row('$phase-plan', 'system only', 0, 0, await plan("SELECT DISTINCT id FROM token_search_parameters WHERE resource_type = 'Observation' AND search_name = 'code' AND token_system = 'x' ORDER BY id LIMIT 20"));
  }
  await round('1-with');
  for (final name in ['idx_token_search_parameters_system_cover', 'idx_reference_search_parameters_value_cover']) {
    await timed('2-drop', 'DROP INDEX $name', () async { await db.customStatement('DROP INDEX IF EXISTS $name'); return 0; });
  }
  await timed('2-analyze', 'ANALYZE', () async { await db.customStatement('ANALYZE'); return 0; });
  await round('3-without');
  await db.close();
  print('done');
}
