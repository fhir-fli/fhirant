// Times fhir_r4_db's schema-7 full search-index rebuild on a loaded
// database, the step fhirant's own migration has to run when it takes that
// schema, and three searches that were wrong or unindexed before it.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';

Future<void> main(List<String> args) async {
  final db = FhirAntDb(NativeDatabase(File('${args[0]}/fhirant.sqlite')));
  Future<void> time(String label, Future<Object?> Function() body) async {
    final t = DateTime.now();
    final result = await body();
    final ms = DateTime.now().difference(t).inMilliseconds;
    final size = result is List ? '${result.length} rows' : '$result';
    print('$label: ${(ms / 1000).toStringAsFixed(1)}s  ($size)');
  }

  Future<int> rows(String table) async =>
      (await db.customSelect('SELECT count(*) AS n FROM $table').getSingle())
          .data['n'] as int;
  print('before: date ${await rows('date_search_parameters')}, '
      'token ${await rows('token_search_parameters')}, '
      'uri ${await rows('uri_search_parameters')}');
  if (!args.contains('--after-only')) {
    await time('rebuildSearchIndex           ', db.rebuildSearchIndex);
  }
  print('after:  date ${await rows('date_search_parameters')}, '
      'token ${await rows('token_search_parameters')}, '
      'uri ${await rows('uri_search_parameters')}');
  await time(
    'Encounter?date=ge2110        ',
    () => db.search(
      resourceType: fhir.R4ResourceType.Encounter,
      searchParameters: const {
        'date': ['ge2110'],
      },
      count: 20,
    ),
  );
  await time(
    'Observation?_profile=...     ',
    () => db.search(
      resourceType: fhir.R4ResourceType.Observation,
      searchParameters: const {
        '_profile': [
          'http://mimic.mit.edu/fhir/mimic/StructureDefinition/mimic-observation-labevents',
        ],
      },
      count: 20,
    ),
  );
  await db.close();
}
