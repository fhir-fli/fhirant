// The specification in `resources` (REVIEW §6.1, decided 2026-09-08): a fresh
// store after the first-boot load, then the encrypted backup with and
// without the tagged specification, then a system export of one type both
// ways. Appended to <dir>/spec_home_bench.tsv as each step finishes.
//   dart run tool/review_2026-09-06/spec_home_bench.dart <dir> <spec-dir>
// ignore_for_file: avoid_print, lines_longer_than_80_chars
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/spec_loader.dart';

Future<void> main(List<String> args) async {
  final dir = args[0];
  final specDir = args[1];
  final tsv = File('$dir/spec_home_bench.tsv');
  if (!tsv.existsSync()) tsv.writeAsStringSync('step\tms\trss_mb\tnote\n');
  void row(String step, int ms, [String note = '']) {
    final rss = ProcessInfo.currentRss ~/ (1024 * 1024);
    tsv.writeAsStringSync('$step\t$ms\t$rss\t$note\n', mode: FileMode.append);
    print('$step: ${ms}ms rss=${rss}MB $note');
  }

  final storePath = '$dir/fresh.sqlite';
  for (final p in [storePath, '$dir/bk_all.sqlite', '$dir/bk_nospec.sqlite']) {
    if (File(p).existsSync()) File(p).deleteSync();
  }
  final db = FhirAntDb(NativeDatabase(File(storePath)));
  await db.initialize();
  row('open fresh', 0);

  var sw = Stopwatch()..start();
  await loadSpecResources(db, specDir);
  Future<int> count(String sql) async =>
      (await db.customSelect(sql).getSingle()).data.values.first! as int;
  final n = await count('SELECT count(*) FROM resources');
  final h = await count('SELECT count(*) FROM resources_history');
  final tagged = await count(
    "SELECT count(*) FROM token_search_parameters WHERE search_name = '_tag' "
    "AND token_system = '$specTagSystem' AND token_value = '$specTagCode'",
  );
  await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
  row(
    'load spec',
    sw.elapsedMilliseconds,
    '$n resources, $h history rows, $tagged tagged, ${File(storePath).lengthSync()} bytes',
  );

  sw = Stopwatch()..start();
  await db.copyEncrypted('$dir/bk_all.sqlite', 'correct horse');
  row(
    'copyEncrypted all',
    sw.elapsedMilliseconds,
    '${File('$dir/bk_all.sqlite').lengthSync()} bytes',
  );
  sw = Stopwatch()..start();
  await db.copyEncrypted(
    '$dir/bk_nospec.sqlite',
    'correct horse',
    withoutTag: specTag,
  );
  row(
    'copyEncrypted withoutTag',
    sw.elapsedMilliseconds,
    '${File('$dir/bk_nospec.sqlite').lengthSync()} bytes',
  );

  for (final type in [
    fhir.R4ResourceType.ValueSet,
    fhir.R4ResourceType.StructureDefinition,
  ]) {
    sw = Stopwatch()..start();
    final all = await db.exportJson(type).length;
    row('exportJson $type', sw.elapsedMilliseconds, '$all lines');
    sw = Stopwatch()..start();
    final kept = await db.exportJson(type, withoutTag: specTag).length;
    row('exportJson $type withoutTag', sw.elapsedMilliseconds, '$kept lines');
  }
  await db.close();

  final copy = FhirAntDb(
    NativeDatabase(
      File('$dir/bk_nospec.sqlite'),
      setup: (raw) => raw
        ..execute("PRAGMA cipher = '${FhirAntDb.cipherScheme}'")
        ..execute("PRAGMA key = 'correct horse'"),
    ),
  );
  Future<int> countIn(String sql) async =>
      (await copy.customSelect(sql).getSingle()).data.values.first! as int;
  row(
      'nospec copy',
      0,
      '${await countIn('SELECT count(*) FROM resources')} resources, '
          '${await countIn('SELECT count(*) FROM token_search_parameters')} token rows, '
          '${await countIn('SELECT count(*) FROM string_search_parameters')} string rows, '
          '${await countIn('SELECT count(*) FROM uri_search_parameters')} uri rows');
  await copy.close();
}
