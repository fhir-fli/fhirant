import 'dart:convert';
import 'dart:isolate';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhir_r4_mapping/fhir_r4_mapping.dart';
import 'package:fhir_r4_path/fhir_r4_path.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/utils/canonical.dart';
import 'package:fhirant_server/src/utils/db_resource_cache.dart';
import 'package:fhirant_server/src/utils/host_resource_cache.dart';
import 'package:fhirant_server/src/utils/operation_outcomes.dart';
import 'package:fhirant_server/src/utils/program_sandbox.dart';
import 'package:shelf/shelf.dart';

/// FHIR Mapping Handler - Transform resources using StructureMap
Future<Response> mappingHandler(
  Request request,
  FhirAntDb db, {
  Duration deadline = kProgramDeadline,
}) async {
  try {
    FhirantLogging().logInfo('Received mapping/transform request');

    final body = await request.readAsString();
    if (body.isEmpty) {
      return outcome(400, fhir.IssueType.invalid, 'Request body is empty');
    }

    Map<String, dynamic> requestJson;
    try {
      requestJson = jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      return outcome(400, fhir.IssueType.invalid, 'Invalid JSON format: $e');
    }

    // R4B OperationDefinition StructureMap-transform (profiles-resources.json,
    // read 2026-09-08): in `source` 0..1 uri (the map's canonical), in
    // `content` 1..1 Resource, out `return`. A Parameters body of that shape
    // is answered here by resolving the StructureMap by `url`; the original
    // `{map: <StructureMap>, source: <resource>}` body stays as an extension
    // (REVIEW-2026-09-08 row 30).
    if (requestJson['resourceType'] == 'Parameters') {
      String? sourceUri;
      Object? content;
      for (final p
          in (requestJson['parameter'] as List<dynamic>? ?? const [])) {
        if (p is! Map<String, dynamic>) continue;
        switch (p['name']) {
          case 'source':
            sourceUri = (p['valueUri'] ??
                p['valueCanonical'] ??
                p['valueString']) as String?;
          case 'content':
            content = p['resource'];
        }
      }
      if (sourceUri == null || sourceUri.isEmpty || content == null) {
        return outcome(
          400,
          fhir.IssueType.invalid,
          'StructureMap-transform takes `source` (the canonical url of a '
          'stored StructureMap) and `content` (the resource to transform)',
        );
      }
      final map = await findOneByCanonical<fhir.StructureMap>(
        db,
        fhir.R4ResourceType.StructureMap,
        sourceUri,
      );
      if (map == null) {
        return outcome(
          404,
          fhir.IssueType.notFound,
          'No StructureMap with url $sourceUri',
        );
      }
      requestJson = {'map': map.toJson(), 'source': content};
    }

    if (requestJson['map'] == null) {
      return outcome(
        400,
        fhir.IssueType.invalid,
        'Missing required field: map (StructureMap)',
      );
    }

    if (requestJson['source'] == null) {
      return outcome(
        400,
        fhir.IssueType.invalid,
        'Missing required field: source (source resource)',
      );
    }

    // Parse StructureMap
    fhir.StructureMap structureMap;
    try {
      structureMap = fhir.StructureMap.fromJson(
        requestJson['map'] as Map<String, dynamic>,
      );
    } catch (e) {
      return outcome(400, fhir.IssueType.invalid, 'Invalid StructureMap: $e');
    }

    // Parse source resource
    fhir.Resource source;
    try {
      final sourceData = requestJson['source'];
      final sourceString =
          sourceData is String ? sourceData : jsonEncode(sourceData);
      source = fhir.Resource.fromJsonString(sourceString);
    } catch (e) {
      return outcome(
        400,
        fhir.IssueType.invalid,
        'Invalid source resource: $e',
      );
    }

    // The engine cannot invent the target: given null it fails with
    // "Unable to create target of type <alias>". StructureMap-transform names
    // the target in the map itself, so build an empty instance of it here.
    final cache = DbResourceCache(db);
    final String? targetType;
    try {
      targetType = await _targetResourceType(structureMap, cache);
    } on TargetTypeAmbiguous catch (e) {
      // Refusing beats guessing: a transform that returned a resource of a
      // type the map did not ask for is a wrong answer, not a limitation.
      return outcome(400, fhir.IssueType.notSupported, e.message);
    }
    if (targetType == null) {
      return outcome(
        400,
        fhir.IssueType.invalid,
        'StructureMap has no structure with mode "target"',
      );
    }

    // Proved buildable here so the refusal is specific; the worker builds
    // its own copy.
    try {
      resourceFromJson(<String, dynamic>{'resourceType': targetType});
    } catch (e) {
      return outcome(
          400,
          fhir.IssueType.notSupported,
          'Unsupported target type "$targetType". The target '
          'structure canonical must name a base FHIR resource; '
          'this server does not resolve a profile or logical '
          'model canonical to its underlying type.');
    }

    // The map is the client's program: it runs in a worker isolate under
    // the deadline (REVIEW-2026-09-17 A9). Map and source cross as JSON;
    // the canonicals the engine resolves while it runs are served from
    // `cache` on this isolate through a HostResourceCache.
    final Map<String, dynamic>? resultJson;
    try {
      resultJson = await runHostedProgram(
        _transformProgram(structureMap.toJson(), source.toJson(), targetType),
        deadline: deadline,
        host: (request) => serveResourceCache(cache, request),
      );
    } on ProgramTimeout catch (e) {
      return outcome(422, fhir.IssueType.tooCostly, '$e');
    }
    // A ProgramFailed (the engine threw) falls through to the catch below
    // and is a 500, as it was on this isolate: the engine reports a failed
    // transform by returning an OperationOutcome, so a throw is its defect.

    if (resultJson == null) {
      return outcome(
        500,
        fhir.IssueType.exception,
        'Mapping returned null result',
      );
    }

    // The engine reports a failed transform by RETURNING an OperationOutcome,
    // not by throwing: transformBuilder catches and calls _createOutcome. A map
    // that leaves a required element unset — Observation.status, Basic.code —
    // fails when the builder is built, and arrives here. Returning that as 200
    // tells the client the transform succeeded and hands it a resource of the
    // wrong type.
    if (resultJson['resourceType'] == 'OperationOutcome' &&
        targetType != 'OperationOutcome') {
      FhirantLogging().logError(
        'Mapping/transformation failed: the engine returned an '
        'OperationOutcome instead of a $targetType',
      );
      return Response(
        422,
        body: jsonEncode(resultJson),
        headers: {'Content-Type': 'application/json'},
      );
    }

    FhirantLogging().logInfo(
      'Resource transformation completed successfully',
    );

    return Response.ok(
      jsonEncode(resultJson),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('Mapping/transformation failed', e, stackTrace);
    return outcome(500, fhir.IssueType.exception, 'Mapping error');
  }
}

/// The worker's side of `$transform`. Built here, in a scope holding only
/// JSON and a type name, because a closure carries its whole scope's
/// context into the isolate: written inline beside the `host` lambda it
/// carried the database and the spawn refused it ("object is unsendable",
/// `tool/review_2026-09-17/fix_a9/06_probe_error.log`).
Future<Map<String, dynamic>?> Function(SendPort) _transformProgram(
  Map<String, dynamic> mapJson,
  Map<String, dynamic> sourceJson,
  String targetType,
) =>
    (host) async {
      final transformed = await fhirMappingEngine(
        fhir.Resource.fromJson(sourceJson).toBuilder,
        fhir.StructureMap.fromJson(mapJson),
        HostResourceCache(host),
        resourceFromJson(<String, dynamic>{'resourceType': targetType}),
      );
      return transformed?.toJson();
    };

/// The resource type a [StructureMap] produces.
///
/// Taken from the FIRST `structure` entry with `mode = target`, whose `url` is
/// typed `canonical(StructureDefinition)` by R4 structuremap.html. That page
/// gives **no rule** for turning the canonical into a type at execution; it
/// says only that "the StructureMap resource assumes that both the source and
/// the target models are fully defined using StructureDefinition resources -
/// either resources, or logical models". So this resolves the definition and
/// reads `StructureDefinition.type`, which structuredefinition.html makes
/// `1..1` and defines as "the type this structure describes". Checked against
/// the published definitions on disk rather than assumed: base `Patient` has
/// `type: "Patient"`, and the profile `us-core-patient` also has
/// `type: "Patient"` — which is what makes a profiled target resolve.
///
/// 🛑 The fallback is a deviation and is labelled as one, and it is now
/// GUARDED. When the canonical is not in the cache or the database, this reads
/// the last path segment of the URL, but only accepts it when it names a real
/// R4 resource type. Unguarded it returned whatever the URL ended with:
/// `us-core-patient` for an unheld profile, and `supplyrequest` for HL7's own
/// published `StructureMap-supplyrequest-transform.json`, whose target
/// canonical is lower case while the type is `SupplyRequest`. Neither is a
/// type this server can build, so both now produce a 400 naming the canonical
/// that could not be resolved. The cure is to POST the StructureDefinition
/// first, which is what makes the map's structures "known to the server".
///
/// `structure` is `0..*`, and structuremap.html gives no rule for choosing
/// among several targets while `$transform` returns exactly one resource. So
/// several target structures resolving to DIFFERENT types is refused rather
/// than silently answered with the first — the spec does not say which is
/// meant, and picking one would be inventing the rule. Several resolving to
/// the same type is unambiguous and is allowed.
Future<String?> _targetResourceType(
  fhir.StructureMap map,
  ResourceCache cache,
) async {
  final found = <String>{};
  for (final structure in map.structure ?? <fhir.StructureMapStructure>[]) {
    if (structure.mode.valueString != 'target') {
      continue;
    }
    final url = structure.url.valueString;
    if (url == null || url.isEmpty) {
      continue;
    }
    final resolved = await cache.getStructureDefinition(url);
    final declared = resolved?.type.valueString;
    if (declared != null && declared.isNotEmpty) {
      found.add(declared);
      continue;
    }
    // Unresolved: the URL's last segment is a guess, and only a guess that
    // names a real resource type is worth making.
    final lastSegment = url.split('/').last;
    if (fhir.R4ResourceType.fromString(lastSegment) != null) {
      found.add(lastSegment);
    } else {
      throw TargetTypeAmbiguous(
        'Cannot resolve the target structure "$url" to a resource type. No '
        'StructureDefinition with that canonical URL is known to this server, '
        'and "$lastSegment" is not an R4 resource type. POST the '
        'StructureDefinition first.',
      );
    }
  }
  if (found.length > 1) {
    final types = (found.toList()..sort()).join(', ');
    throw TargetTypeAmbiguous(
      'This StructureMap declares target structures of more than one type '
      '($types). The operation returns a single resource and '
      'structuremap.html gives no rule for choosing among them, so this '
      'server refuses rather than picking one.',
    );
  }
  return found.isEmpty ? null : found.first;
}

/// Thrown when a map's target type cannot be determined without guessing.
class TargetTypeAmbiguous implements Exception {
  /// Creates a refusal explaining [message].
  const TargetTypeAmbiguous(this.message);

  /// What could not be decided, and what the caller can do about it.
  final String message;

  @override
  String toString() => message;
}
