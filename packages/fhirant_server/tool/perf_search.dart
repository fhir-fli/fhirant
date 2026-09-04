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

  // Two token parameters, so the SQL intersection path is measured.
  await time(
    'search   status=final AND code   ',
    () => db.search(
      resourceType: fhir.R4ResourceType.Observation,
      searchParameters: const {
        'status': ['final'],
        'code': ['227969'],
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

  // Date eq over a month and a year (R4B 3.1.1.4.7 intervals). MIMIC's
  // dates are shifted a century forward; 2116-12 holds 30,652 Observation
  // dates and 2137 holds 60,056.
  await time(
    'search   date=2116-12            ',
    () => db.search(
      resourceType: fhir.R4ResourceType.Observation,
      searchParameters: const {
        'date': ['2116-12'],
      },
      count: 20,
    ),
  );
  await time(
    'search   date=2137 AND status    ',
    () => db.search(
      resourceType: fhir.R4ResourceType.Observation,
      searchParameters: const {
        'date': ['2137'],
        'status': ['final'],
      },
      count: 20,
    ),
  );
  // Encounter.date is Encounter.period: 637 Encounters, zero index rows
  // before fhir_r4_db schema 8.
  await time(
    'search   Encounter?date=ge2110   ',
    () => db.search(
      resourceType: fhir.R4ResourceType.Encounter,
      searchParameters: const {
        'date': ['ge2110'],
      },
      count: 20,
    ),
  );

  // A string parameter with real volume: value-string starting with "no"
  // matches "none" and "no" and "normal", ~39k Observations.
  await time(
    'search   string (value-string=no) ',
    () => db.search(
      resourceType: fhir.R4ResourceType.Observation,
      searchParameters: const {
        'value-string': ['no'],
      },
      count: 20,
    ),
  );

  // The query a real client makes: one patient's observations of one code.
  // This patient has 48,554 Observations; code 227969 has 19,330 in all.
  await time(
    'search   subject AND code         ',
    () => db.search(
      resourceType: fhir.R4ResourceType.Observation,
      searchParameters: const {
        'subject': ['Patient/77e10fd0-6a1c-5547-a130-fae1341acf36'],
        'code': ['227969'],
      },
      count: 20,
    ),
  );

  // The same query for a patient of realistic size: 963 Observations, 35 of
  // this code. The smallest MIMIC patient has 415; the 48,554 one above is
  // the largest.
  await time(
    'search   subject(963) AND code   ',
    () => db.search(
      resourceType: fhir.R4ResourceType.Observation,
      searchParameters: const {
        'subject': ['Patient/42f0ed8f-d744-5edb-a05d-8e011c1fbd64'],
        'code': ['227969'],
      },
      count: 20,
    ),
  );

  // Quantity, R4B 3.1.1.4.11 forms: value alone, and value|system|code.
  // value-quantity has 366,433 rows here; >100 matches 50,030 of them, and
  // >100 in the MIMIC unit system as mg/dL matches 4,098.
  await time(
    'search   quantity gt100           ',
    () => db.search(
      resourceType: fhir.R4ResourceType.Observation,
      searchParameters: const {
        'value-quantity': ['gt100'],
      },
      count: 20,
    ),
  );
  await time(
    'search   quantity gt100|sys|mg/dL ',
    () => db.search(
      resourceType: fhir.R4ResourceType.Observation,
      searchParameters: const {
        'value-quantity': [
          'gt100|http://mimic.mit.edu/fhir/mimic/CodeSystem/mimic-units|mg/dL',
        ],
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
