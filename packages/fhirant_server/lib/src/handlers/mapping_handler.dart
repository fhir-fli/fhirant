import 'dart:convert';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhir_r4_mapping/fhir_r4_mapping.dart';
import 'package:fhir_r4_path/fhir_r4_path.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/utils/db_resource_cache.dart';
import 'package:shelf/shelf.dart';

/// FHIR Mapping Handler - Transform resources using StructureMap
Future<Response> mappingHandler(Request request, FhirAntDb db) async {
  try {
    FhirantLogging().logInfo('Received mapping/transform request');

    final body = await request.readAsString();
    if (body.isEmpty) {
      return Response(
        400,
        body: jsonEncode({
          'resourceType': 'OperationOutcome',
          'issue': [
            {
              'severity': 'error',
              'code': 'invalid',
              'diagnostics': 'Request body is empty',
            }
          ],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    Map<String, dynamic> requestJson;
    try {
      requestJson = jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      return Response(
        400,
        body: jsonEncode({
          'resourceType': 'OperationOutcome',
          'issue': [
            {
              'severity': 'error',
              'code': 'invalid',
              'diagnostics': 'Invalid JSON format: $e',
            }
          ],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    if (requestJson['map'] == null) {
      return Response(
        400,
        body: jsonEncode({
          'resourceType': 'OperationOutcome',
          'issue': [
            {
              'severity': 'error',
              'code': 'invalid',
              'diagnostics': 'Missing required field: map (StructureMap)',
            }
          ],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    if (requestJson['source'] == null) {
      return Response(
        400,
        body: jsonEncode({
          'resourceType': 'OperationOutcome',
          'issue': [
            {
              'severity': 'error',
              'code': 'invalid',
              'diagnostics': 'Missing required field: source (source resource)',
            }
          ],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Parse StructureMap
    fhir.StructureMap structureMap;
    try {
      structureMap = fhir.StructureMap.fromJson(
        requestJson['map'] as Map<String, dynamic>,
      );
    } catch (e) {
      return Response(
        400,
        body: jsonEncode({
          'resourceType': 'OperationOutcome',
          'issue': [
            {
              'severity': 'error',
              'code': 'invalid',
              'diagnostics': 'Invalid StructureMap: $e',
            }
          ],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Parse source resource
    fhir.Resource source;
    try {
      final sourceData = requestJson['source'];
      final sourceString =
          sourceData is String ? sourceData : jsonEncode(sourceData);
      source = fhir.Resource.fromJsonString(sourceString);
    } catch (e) {
      return Response(
        400,
        body: jsonEncode({
          'resourceType': 'OperationOutcome',
          'issue': [
            {
              'severity': 'error',
              'code': 'invalid',
              'diagnostics': 'Invalid source resource: $e',
            }
          ],
        }),
        headers: {'Content-Type': 'application/json'},
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
      return Response(
        400,
        body: jsonEncode({
          'resourceType': 'OperationOutcome',
          'issue': [
            {
              'severity': 'error',
              'code': 'not-supported',
              'diagnostics': e.message,
            },
          ],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
    if (targetType == null) {
      return Response(
        400,
        body: jsonEncode({
          'resourceType': 'OperationOutcome',
          'issue': [
            {
              'severity': 'error',
              'code': 'invalid',
              'diagnostics': 'StructureMap has no structure with mode "target"',
            }
          ],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    ResourceBuilder targetBuilder;
    try {
      targetBuilder = resourceFromJson(<String, dynamic>{
        'resourceType': targetType,
      });
    } catch (e) {
      return Response(
        400,
        body: jsonEncode({
          'resourceType': 'OperationOutcome',
          'issue': [
            {
              'severity': 'error',
              'code': 'not-supported',
              'diagnostics':
                  'Unsupported target type "$targetType". The target '
                      'structure canonical must name a base FHIR resource; '
                      'this server does not resolve a profile or logical '
                      'model canonical to its underlying type.',
            }
          ],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Convert Resource to builder for mapping engine
    // Resources have a toBuilder() method that returns FhirBaseBuilder
    final sourceBuilder = source.toBuilder;

    // Execute mapping
    final transformed = await fhirMappingEngine(
      sourceBuilder,
      structureMap,
      cache,
      targetBuilder,
    );

    if (transformed == null) {
      return Response(
        500,
        body: jsonEncode({
          'resourceType': 'OperationOutcome',
          'issue': [
            {
              'severity': 'error',
              'code': 'exception',
              'diagnostics': 'Mapping returned null result',
            }
          ],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // The engine reports a failed transform by RETURNING an OperationOutcome,
    // not by throwing: transformBuilder catches and calls _createOutcome. A map
    // that leaves a required element unset — Observation.status, Basic.code —
    // fails when the builder is built, and arrives here. Returning that as 200
    // tells the client the transform succeeded and hands it a resource of the
    // wrong type.
    final resultJson = transformed.toJson();
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
    return Response(
      500,
      body: jsonEncode({
        'resourceType': 'OperationOutcome',
        'issue': [
          {
            'severity': 'error',
            'code': 'exception',
            'diagnostics': 'Mapping error',
          }
        ],
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

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
