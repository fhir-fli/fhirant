// Times fhir_r4_db's schema-8 date-index rebuild on a loaded database, the
// step fhirant's own migration has to run when it takes that schema.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';

Future<void> main(List<String> args) async {
  final db = FhirAntDb(NativeDatabase(File('${args[0]}/fhirant.sqlite')));
  final before = await db
      .customSelect('SELECT count(*) AS n FROM date_search_parameters')
      .getSingle();
  print('date rows before: ${before.data['n']}');
  final t = DateTime.now();
  await db.rebuildDateIndex();
  final ms = DateTime.now().difference(t).inMilliseconds;
  final after = await db
      .customSelect('SELECT count(*) AS n FROM date_search_parameters')
      .getSingle();
  final encounters = await db
      .customSelect(
        'SELECT count(*) AS n FROM date_search_parameters '
        "WHERE resource_type = 'Encounter'",
      )
      .getSingle();
  print(
    'rebuilt in ${(ms / 1000).toStringAsFixed(1)}s: '
    '${after.data['n']} rows, Encounter ${encounters.data['n']}',
  );
  await db.close();
}
