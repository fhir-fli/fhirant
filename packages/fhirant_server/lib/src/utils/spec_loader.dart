import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhir_r4_bulk/fhir_r4_bulk.dart' show NdjsonStream;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';

/// How many resources go to the store in one transaction while loading.
///
/// Twenty, and an event-loop turn between chunks: the store runs its SQL on
/// the calling isolate and the awaits inside a chunk complete as microtasks,
/// so without the turn the UI isolate in the app is held for a whole file.
/// Measured 2026-09-08 on this desktop with the 48 MB set: chunks of 100
/// with no turn held the loop 1.4 s (files) and 5.4 s (assets) at a stretch;
/// see the note on [loadSpecLines].
const _chunkSize = 20;

/// The `meta.tag` every resource of the specification load carries, so the
/// store can tell a deployment's own data from the 4,212 conformance
/// resources that ship with the server. A system-level `$export` with no
/// `_type` and `$backup` leave tagged resources out; REST, a resource's own
/// `_history` and the dashboard see them as any resource (REVIEW-2026-09-06
/// §6.1, decided 2026-09-08: the specification stays in `resources`).
const specTagSystem = 'http://fhirant.fhir-fli.dev/CodeSystem/tags';

/// The code of [specTag].
const specTagCode = 'spec';

/// The tag itself, as written into `meta.tag`.
final fhir.Coding specTag = fhir.Coding(
  system: specTagSystem.toFhirUri,
  code: specTagCode.toFhirCode,
);

/// Whether [resource] carries [specTag].
bool isSpecResource(fhir.Resource resource) =>
    resource.meta?.tag?.any(
      (t) =>
          t.system?.toString() == specTagSystem &&
          t.code?.toString() == specTagCode,
    ) ??
    false;

/// [resource] with [specTag] added to its `meta.tag`.
fhir.Resource _tagged(fhir.Resource resource) {
  final meta = resource.meta;
  return resource.copyWith(
    meta: (meta ?? const fhir.FhirMeta()).copyWith(
      tag: [...?meta?.tag, specTag],
    ),
  );
}

/// Whether the store already holds the specification: the loader runs once,
/// on the first boot, and a store with CodeSystems in it has had it.
Future<bool> specResourcesLoaded(FhirAntDb db) async =>
    await db.getResourceCount(fhir.R4ResourceType.CodeSystem) > 0;

/// Loads all FHIR R4 spec canonical resources from NDJSON files into the
/// database on first boot.
///
/// This includes StructureDefinitions, SearchParameters, ValueSets,
/// CodeSystems, ConceptMaps, NamingSystems, OperationDefinitions,
/// CompartmentDefinitions, and CapabilityStatements.
///
/// Skips loading if the database already contains CodeSystem resources.
/// This is the CLI's and the container's path; the app loads the same set
/// from its asset bundle through [loadSpecResourcesFromAssets].
Future<void> loadSpecResources(FhirAntDb db, String specPath) async {
  final logger = FhirantLogging();

  if (await specResourcesLoaded(db)) {
    logger.logInfo('Spec resources already loaded, skipping');
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
    final lines = NdjsonStream.lines(file.openRead());
    final (loaded, errors) = await loadSpecLines(db, lines, fileName);
    totalLoaded += loaded;
    totalErrors += errors;
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

  _report(totalLoaded, totalErrors);
}

/// Loads the specification from an asset bundle: [assetKeys] are the NDJSON
/// assets (`assets/fhir_spec/*.ndjson`), [loadBytes] reads one (the app
/// passes `rootBundle.load`). Skips when the store already holds the
/// specification. The mobile app never loaded the specification, so
/// `$validate` on the phone answered 422 for any bound element
/// (REVIEW-2026-09-06 finding 43).
///
/// The bytes of one asset are decoded and split in pieces of
/// [_assetPieceBytes], so the 31 MB profiles file is never turned into lines
/// in one synchronous step; lines are parsed and saved in chunks as they
/// come, nothing accumulates across files.
Future<void> loadSpecResourcesFromAssets(
  FhirAntDb db, {
  required Iterable<String> assetKeys,
  required Future<ByteData> Function(String key) loadBytes,
}) async {
  final logger = FhirantLogging();
  if (await specResourcesLoaded(db)) {
    logger.logInfo('Spec resources already loaded, skipping');
    return;
  }
  final keys = assetKeys.where((k) => k.endsWith('.ndjson')).toList()..sort();
  if (keys.isEmpty) {
    logger.logWarning('No spec assets in the bundle, skipping');
    return;
  }
  logger.logInfo(
    'Loading FHIR R4 spec canonical resources from the app bundle',
  );
  var totalLoaded = 0;
  var totalErrors = 0;
  for (final key in keys) {
    final data = await loadBytes(key);
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final lines = NdjsonStream.lines(_pieces(bytes));
    final (loaded, errors) = await loadSpecLines(
      db,
      lines,
      key.split('/').last,
    );
    totalLoaded += loaded;
    totalErrors += errors;
  }
  _report(totalLoaded, totalErrors);
}

/// The size of one piece of an asset handed to the decoder at a time.
const int _assetPieceBytes = 256 * 1024;

/// [bytes] in pieces, each after an event-loop turn.
Stream<List<int>> _pieces(Uint8List bytes) async* {
  for (var i = 0; i < bytes.length; i += _assetPieceBytes) {
    final end = i + _assetPieceBytes > bytes.length
        ? bytes.length
        : i + _assetPieceBytes;
    yield Uint8List.sublistView(bytes, i, end);
    await Future<void>.delayed(Duration.zero);
  }
}

/// Parses [lines] (one resource each) and saves them in transactions of
/// [_chunkSize], never holding more than one chunk of parsed resources.
/// Returns how many were saved and how many lines failed to parse. The
/// previous loader parsed a whole file into a list first, which on the
/// 31 MB profiles-resources file held every StructureDefinition at once
/// (813 MB RSS measured 2026-09-08 for the whole set).
///
/// Every resource is saved tagged [specTag]. No first version writes a
/// history row since fhir_r4_db schema 14 (the current version is stored
/// once); the load used to write a second 48 MB copy of the set into
/// `resources_history` (measured 2026-09-08 on a fresh store: 4,213 history
/// rows for 4,212 resources). A later update of a specification resource
/// moves the replaced version into history as any save does.
Future<(int, int)> loadSpecLines(
  FhirAntDb db,
  Stream<String> lines,
  String fileName,
) async {
  var loaded = 0;
  var errors = 0;
  var chunk = <fhir.Resource>[];
  Future<void> save() async {
    if (chunk.isEmpty) return;
    await db.saveResources(chunk);
    loaded += chunk.length;
    chunk = <fhir.Resource>[];
    // A real event-loop turn, so timers, the UI and other requests run
    // between chunks.
    await Future<void>.delayed(Duration.zero);
  }

  final resources = NdjsonStream.resources(
    lines.where((line) => line.trim().isNotEmpty),
    onBadLine: (_, __) => errors++,
  );
  await for (final resource in resources) {
    chunk.add(_tagged(resource));
    if (chunk.length >= _chunkSize) await save();
  }
  await save();
  FhirantLogging().logInfo('Loaded $loaded resources from $fileName');
  return (loaded, errors);
}

void _report(int totalLoaded, int totalErrors) {
  final logger = FhirantLogging();
  if (totalErrors > 0) {
    logger.logWarning('$totalErrors resources failed to parse');
  }
  logger.logInfo(
    'Spec loading complete: $totalLoaded canonical resources loaded',
  );
}
