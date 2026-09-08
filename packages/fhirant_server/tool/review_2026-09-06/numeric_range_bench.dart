// REVIEW-2026-09-06 §6.1: number and quantity prefixes on the MIMIC copy,
// through FhirAntDb.search, count 20. One row per query per run.
//
//   dart run tool/review_2026-09-06/numeric_range_bench.dart <dir> <tsv> <label>
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';

Future<void> main(List<String> args) async {
  final dir = args[0];
  final tsv = File(args[1]);
  final label = args[2];
  if (!tsv.existsSync()) {
    tsv.writeAsStringSync('label\tquery\tround\tms\thits\tpaged_in_sql\n');
  }
  final db = FhirAntDb(NativeDatabase(File('$dir/fhirant.sqlite')));
  await db.initialize();
  const queries = {
    'value-quantity=gt100': {
      'value-quantity': ['gt100'],
    },
    'value-quantity=lt5': {
      'value-quantity': ['lt5'],
    },
    'value-quantity=ge100': {
      'value-quantity': ['ge100'],
    },
    'value-quantity=le5': {
      'value-quantity': ['le5'],
    },
    'value-quantity=100': {
      'value-quantity': ['100'],
    },
    'value-quantity=ap100': {
      'value-quantity': ['ap100'],
    },
    'value-quantity=gt100&code=8867-4': {
      'value-quantity': ['gt100'],
      'code': ['http://loinc.org|8867-4'],
    },
    // Sparse ranges: the page cannot stop early, so the predicate's shape
    // decides whether the index is a range seek or a scan.
    'value-quantity=gt99999': {
      'value-quantity': ['gt99999'],
    },
    'value-quantity=lt0.0001': {
      'value-quantity': ['lt0.0001'],
    },
    'value-quantity=sa99999': {
      'value-quantity': ['sa99999'],
    },
    'value-quantity=12345.678': {
      'value-quantity': ['12345.678'],
    },
    // Date and _lastUpdated ranges share the single-range page rule, so a
    // change to it is measured on them too (the §4.7 cases).
    'date=ge2150': {
      'date': ['ge2150'],
    },
    'date=2137': {
      'date': ['2137'],
    },
    '_lastUpdated=ge2999': {
      '_lastUpdated': ['ge2999'],
    },
    '_lastUpdated=ge2100': {
      '_lastUpdated': ['ge2100'],
    },
  };
  // Counts read every match: no LIMIT to stop at.
  const counts = {
    'count value-quantity=gt100': {
      'value-quantity': ['gt100'],
    },
    'count value-quantity=gt99999': {
      'value-quantity': ['gt99999'],
    },
    'count value-quantity=le5': {
      'value-quantity': ['le5'],
    },
    'count date=ge2150': {
      'date': ['ge2150'],
    },
  };
  for (final entry in queries.entries) {
    for (var round = 1; round <= 2; round++) {
      final sw = Stopwatch()..start();
      final hits = await db.search(
        resourceType: fhir.R4ResourceType.Observation,
        searchParameters: entry.value,
        count: 20,
      );
      sw.stop();
      final row = '$label\t${entry.key}\t$round\t${sw.elapsedMilliseconds}\t'
          '${hits.length}\t${db.fhirDao.lastSearchPagedInSql}\n';
      tsv.writeAsStringSync(row, mode: FileMode.append);
      stdout.write(row);
    }
  }
  for (final entry in counts.entries) {
    for (var round = 1; round <= 2; round++) {
      final sw = Stopwatch()..start();
      final n = await db.searchCount(
        resourceType: fhir.R4ResourceType.Observation,
        searchParameters: entry.value,
      );
      sw.stop();
      final row = '$label\t${entry.key}\t$round\t${sw.elapsedMilliseconds}\t'
          '$n\t-\n';
      tsv.writeAsStringSync(row, mode: FileMode.append);
      stdout.write(row);
    }
  }
  await db.close();
  exit(0);
}
