import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';

/// Loads all FHIR R4 spec canonical resources from NDJSON files into the
/// database on first boot.
///
/// This includes StructureDefinitions, SearchParameters, ValueSets,
/// CodeSystems, ConceptMaps, NamingSystems, OperationDefinitions,
/// CompartmentDefinitions, and CapabilityStatements.
///
/// Skips loading if the database already contains CodeSystem resources.
Future<void> loadSpecResources(FhirAntDb db, String specPath) async {
  final logger = FhirantLogging();

  // Check if spec resources are already loaded
  final csCount = await db.getResourceCount(fhir.R4ResourceType.CodeSystem);
  if (csCount > 0) {
    logger.logInfo(
      'Spec resources already loaded ($csCount CodeSystems), skipping',
    );
    return;
  }

  final specDir = Directory(specPath);
  if (!specDir.existsSync()) {
    logger.logWarning('Spec directory not found at $specPath, skipping');
    return;
  }

  logger.logInfo('Loading FHIR R4 spec canonical resources from $specPath');

  var totalLoaded = 0;
  var totalErrors = 0;

  // Load all NDJSON files in the spec directory
  final ndjsonFiles = specDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.ndjson'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in ndjsonFiles) {
    final fileName = file.path.split('/').last;
    final resources = <fhir.Resource>[];
    final lines = await file.readAsLines();

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        resources.add(fhir.Resource.fromJson(json));
      } catch (e) {
        totalErrors++;
      }
    }

    if (resources.isNotEmpty) {
      // Batch save in chunks to avoid memory pressure
      const chunkSize = 100;
      for (var i = 0; i < resources.length; i += chunkSize) {
        final end =
            (i + chunkSize > resources.length) ? resources.length : i + chunkSize;
        final chunk = resources.sublist(i, end);
        await db.saveResources(chunk);
      }
      logger.logInfo(
        'Loaded ${resources.length} resources from $fileName',
      );
      totalLoaded += resources.length;
    }
  }

  // Load individual JSON fixtures (e.g. NamingSystem example)
  final fixturesPath =
      specPath.replaceAll('/fhir_spec', '/terminology_fixtures');
  final fixturesDir = Directory(fixturesPath);
  if (fixturesDir.existsSync()) {
    final fixtureFiles = fixturesDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'));
    for (final file in fixtureFiles) {
      try {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final resource = fhir.Resource.fromJson(json);
        await db.saveResource(resource);
        totalLoaded++;
      } catch (e) {
        totalErrors++;
        logger.logWarning('Failed to load fixture ${file.path}: $e');
      }
    }
  }

  if (totalErrors > 0) {
    logger.logWarning('$totalErrors resources failed to parse');
  }
  logger.logInfo(
    'Spec loading complete: $totalLoaded canonical resources loaded',
  );
}
