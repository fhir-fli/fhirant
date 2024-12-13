// ignore_for_file: avoid_print

import 'dart:convert';
import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant/db/fhir_database.dart' as fhirant;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = fhirant.FhirDb();
  final start = DateTime.now();
  const password = 'super_secret_password';
  const dbPath = './fhir_database.sqlite';
  print('dbPath: $dbPath');

  // Initialize the database
  await db.init(path: dbPath, pw: password);

  // List of NDJSON files in the assets directory
  const ndjsonFiles = [
    'assets/Condition.ndjson',
    'assets/MedicationDispense.ndjson',
    'assets/ObservationMicroOrg.ndjson',
    'assets/ProcedureICU.ndjson',
    'assets/EncounterICU.ndjson',
    'assets/Medication.ndjson',
    'assets/ObservationMicroSusc.ndjson',
    'assets/Procedure.ndjson',
    'assets/Encounter.ndjson',
    'assets/MedicationRequest.ndjson',
    'assets/ObservationMicroTest.ndjson',
    'assets/SpecimenLab.ndjson',
    'assets/Location.ndjson',
    'assets/ObservationChartevents.ndjson',
    'assets/ObservationOutputevents.ndjson',
    'assets/Specimen.ndjson',
    'assets/MedicationAdministrationICU.ndjson',
    'assets/ObservationDatetimeevents.ndjson',
    'assets/Organization.ndjson',
    'assets/MedicationAdministration.ndjson',
    'assets/ObservationLabevents.ndjson',
    'assets/Patient.ndjson',
  ];

  for (final filePath in ndjsonFiles) {
    await processNdjsonFile(db, filePath);
  }

  final end = DateTime.now();
  print('Processed all files in ${end.difference(start).inSeconds} seconds');
}

/// Process an NDJSON file and insert the resources into the database
Future<void> processNdjsonFile(fhirant.FhirDb db, String filePath) async {
  final stopwatch = Stopwatch()..start();

  try {
    // Load the NDJSON file from assets
    final fileContents = await rootBundle.loadString(filePath);
    final lines = LineSplitter.split(fileContents);

    final resources = <Map<String, dynamic>>[];

    // Parse each line as a FHIR resource
    for (final line in lines) {
      if (line.isEmpty) {
        continue;
      }
      final resource = jsonDecode(line) as Map<String, dynamic>;
      resources.add(resource);
    }

    final resourceType = (jsonDecode(lines.first)
        as Map<String, dynamic>)['resourceType'] as String;

    // Batch insert resources into the database
    await db.batchInsert(R4ResourceType.fromString(resourceType)!, resources);

    print('Processed $filePath in ${stopwatch.elapsed}');
  } catch (e) {
    print('Error processing file $filePath: $e');
  }
}
