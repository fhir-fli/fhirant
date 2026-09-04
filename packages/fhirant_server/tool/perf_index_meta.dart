// Times fhir_r4_db's schema-9 meta indexing (_tag, _security, _profile,
// _source rows for every stored resource), and the _profile search before
// and after it.
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
    print(
      '$label: ${(ms / 1000).toStringAsFixed(2)}s  ($size)',
    );
  }

  Future<List<fhir.Resource>> profileSearch() => db.search(
        resourceType: fhir.R4ResourceType.Observation,
        searchParameters: const {
          '_profile': [
            'http://mimic.mit.edu/fhir/mimic/StructureDefinition/mimic-observation-labevents',
          ],
        },
        count: 20,
      );
  if (!args.contains('--after-only')) {
    await time('_profile search, before      ', profileSearch);
    await time('indexMetaParameters          ', () async {
      await db.indexMetaParameters();
      final n = await db
          .customSelect(
            'SELECT count(*) AS n FROM uri_search_parameters '
            "WHERE search_name = '_profile'",
          )
          .getSingle();
      return n.data['n'];
    });
  }
  await time('_profile search, after       ', profileSearch);
  await time(
    '_profile AND status=final    ',
    () => db.search(
      resourceType: fhir.R4ResourceType.Observation,
      searchParameters: const {
        '_profile': [
          'http://mimic.mit.edu/fhir/mimic/StructureDefinition/mimic-observation-labevents',
        ],
        'status': ['final'],
      },
      count: 20,
    ),
  );
  await db.close();
}
