// Times the two halves of a search over a loaded database: resolving the
// matching ids, and hydrating them into resources.
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
    print('$label: ${(ms / 1000).toStringAsFixed(2)}s  ($size)');
  }

  await time(
    'searchCount status=final          ',
    () => db.searchCount(
      resourceType: fhir.R4ResourceType.Observation,
      searchParameters: const {
        'status': ['final'],
      },
    ),
  );

  await time(
    'search   status=final, count 20   ',
    () => db.search(
      resourceType: fhir.R4ResourceType.Observation,
      searchParameters: const {
        'status': ['final'],
      },
      count: 20,
    ),
  );

  // Other parameter TYPES, so the id-column change can be measured where it
  // applies: the status query above is a token search.
  await time(
    'search   date  (Observation?date) ',
    () => db.search(
      resourceType: fhir.R4ResourceType.Observation,
      searchParameters: const {
        'date': ['gt2100-01-01'],
      },
      count: 20,
    ),
  );

  await time(
    'search   reference (subject)      ',
    () => db.search(
      resourceType: fhir.R4ResourceType.Observation,
      searchParameters: const {
        'subject': ['Patient/does-not-exist'],
      },
      count: 20,
    ),
  );

  await time(
    'search   _id single               ',
    () => db.search(
      resourceType: fhir.R4ResourceType.Observation,
      searchParameters: const {
        '_id': ['does-not-exist'],
      },
    ),
  );

  await db.close();
}
