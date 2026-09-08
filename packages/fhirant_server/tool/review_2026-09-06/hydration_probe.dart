// Where does an equality search's time go: the id page, or the 20 reads that
// hydrate it? Run on the MIMIC copy, prints and appends to <db-dir>/hydration_probe.tsv.
// ignore_for_file: avoid_print, lines_longer_than_80_chars
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';

Future<void> main(List<String> args) async {
  final dir = args[0];
  final out = File('$dir/hydration_probe.tsv');
  if (!out.existsSync()) out.writeAsStringSync('round\tstep\tms\n');
  final db = FhirAntDb(NativeDatabase(File('$dir/fhirant.sqlite')));
  await db.customSelect('SELECT 1').get();
  const big = '77e10fd0-6a1c-5547-a130-fae1341acf36';
  Future<void> timed(int round, String step, Future<void> Function() body) async {
    final sw = Stopwatch()..start();
    await body();
    out.writeAsStringSync('$round\t$step\t${sw.elapsedMilliseconds}\n', mode: FileMode.append);
    print('[$round] $step: ${sw.elapsedMilliseconds} ms');
  }
  for (var round = 1; round <= 3; round++) {
    var ids = <String>[];
    await timed(round, 'DAO search subject=big count 20', () async {
      final r = await db.search(resourceType: fhir.R4ResourceType.Observation, searchParameters: {'subject': ['Patient/$big']}, count: 20);
      ids = r.map((e) => e.id!.valueString!).toList();
    });
    await timed(round, 'SQL id page (covering index)', () async {
      await db.customSelect("SELECT DISTINCT id FROM reference_search_parameters WHERE resource_type = 'Observation' AND search_name = 'subject' AND reference_resource_type = 'Patient' AND reference_id_part = '$big' ORDER BY id LIMIT 20").get();
    });
    await timed(round, '20 x getResource', () async {
      for (final id in ids) {
        await db.getResource(fhir.R4ResourceType.Observation, id);
      }
    });
    await timed(round, 'SQL 20 rows IN (...)', () async {
      final ph = List.filled(ids.length, '?').join(',');
      await db.customSelect("SELECT resource FROM resources WHERE resource_type = 'Observation' AND id IN ($ph)", variables: [for (final id in ids) Variable.withString(id)]).get();
    });
    await timed(round, 'DAO search code=227969 count 20', () async {
      await db.search(resourceType: fhir.R4ResourceType.Observation, searchParameters: {'code': ['227969']}, count: 20);
    });
  }
  await db.close();
}
