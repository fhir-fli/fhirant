import 'dart:convert';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhir_r4_mapping/fhir_r4_mapping.dart';
import 'package:fhir_r4_path/fhir_r4_path.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:http/http.dart' show Client;
import 'package:shelf/shelf.dart';

/// Simple ResourceCache implementation for mapping
class SimpleResourceCache implements ResourceCache {
  final Map<String, fhir.Resource> _cache = {};

  Future<fhir.Resource?> findResourceById(
    String resourceType,
    String id,
  ) async {
    return _cache['$resourceType/$id'];
  }

  Future<fhir.Resource?> findResourceByUrl(String url) async {
    return _cache[url];
  }

  @override
  Future<void> saveCanonicalResource(fhir.Resource resource) async {
    if (resource is fhir.CanonicalResource && resource.url != null) {
      _cache[resource.url!.valueString ?? ''] = resource;
    }
  }

  @override
  Future<T?> getCanonicalResource<T extends fhir.CanonicalResource>(
    String url, [
    String? version,
  ]) async {
    final resource = _cache[url];
    return resource is T? ? resource : null;
  }

  @override
  // TODO(fhirant): implement client
  Client? get client => throw UnimplementedError();

  @override
  Future<fhir.CodeSystem?> getCodeSystem(String url, [String? version]) {
    // TODO(fhirant): implement getCodeSystem
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>?> getResourceMap(String url) {
    // TODO(fhirant): implement getResourceMap
    throw UnimplementedError();
  }

  @override
  Future<List<String>> getResourceNames() {
    // TODO(fhirant): implement getResourceNames
    throw UnimplementedError();
  }

  @override
  Future<fhir.StructureDefinition?> getStructureDefinition(String url) {
    // TODO(fhirant): implement getStructureDefinition
    throw UnimplementedError();
  }

  @override
  Future<List<fhir.StructureDefinition>> getStructureDefinitions() {
    // TODO(fhirant): implement getStructureDefinitions
    throw UnimplementedError();
  }
}

/// FHIR Mapping Handler - Transform resources using StructureMap
Future<Response> mappingHandler(Request request) async {
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
    final targetType = _targetResourceType(structureMap);
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
                  'Unsupported target type "$targetType": only FHIR resource '
                      'types can be produced by this server',
            }
          ],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Create resource cache for mapping
    final cache = SimpleResourceCache();

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

/// The resource type a [StructureMap] produces, taken from its `structure`
/// entry with `mode = target`. R4 structuremap.html: the canonical URL of a
/// resource StructureDefinition ends in the resource type name.
String? _targetResourceType(fhir.StructureMap map) {
  for (final structure in map.structure ?? <fhir.StructureMapStructure>[]) {
    if (structure.mode.valueString != 'target') {
      continue;
    }
    final url = structure.url.valueString;
    if (url == null || url.isEmpty) {
      continue;
    }
    final lastSegment = url.split('/').last;
    if (lastSegment.isNotEmpty) {
      return lastSegment;
    }
  }
  return null;
}
