import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';

/// Loads FHIR R4 spec terminology resources (CodeSystem, ValueSet, ConceptMap,
/// NamingSystem) from NDJSON files into the database on first boot.
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

  logger.logInfo('Loading FHIR R4 spec terminology resources from $specPath');

  // Resource types we want to load for terminology support
  const targetTypes = {
    'CodeSystem',
    'ValueSet',
    'ConceptMap',
    'NamingSystem',
  };

  // Files that contain terminology resources
  const filesToLoad = [
    'valuesets.ndjson', // Contains CodeSystem + ValueSet
    'conceptmaps.ndjson', // Contains ConceptMap
  ];

  var totalLoaded = 0;
  var totalErrors = 0;

  for (final fileName in filesToLoad) {
    final file = File('$specPath/$fileName');
    if (!file.existsSync()) {
      logger.logWarning('Spec file not found: $specPath/$fileName');
      continue;
    }

    final resources = <fhir.Resource>[];
    final lines = await file.readAsLines();

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        final resourceType = json['resourceType'] as String?;
        if (resourceType != null && targetTypes.contains(resourceType)) {
          resources.add(fhir.Resource.fromJson(json));
        }
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

  if (totalErrors > 0) {
    logger.logWarning('$totalErrors resources failed to parse');
  }
  logger.logInfo(
    'Spec loading complete: $totalLoaded terminology resources loaded',
  );
}
