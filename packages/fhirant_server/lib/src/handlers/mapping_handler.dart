import 'dart:convert';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhir_r4_mapping/fhir_r4_mapping.dart';
import 'package:fhir_r4_path/fhir_r4_path.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:http/src/client.dart';
import 'package:shelf/shelf.dart';

/// Simple ResourceCache implementation for mapping
class SimpleResourceCache implements ResourceCache {
  final Map<String, fhir.Resource> _cache = {};

  Future<fhir.Resource?> findResourceById(
      String resourceType, String id) async {
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

  Future<T?> getCanonicalResource<T extends fhir.CanonicalResource>(
    String url, [
    String? version,
  ]) async {
    final resource = _cache[url];
    return resource is T? ? resource : null;
  }

  @override
  // TODO: implement client
  Client? get client => throw UnimplementedError();

  @override
  Future<fhir.CodeSystem?> getCodeSystem(String url, [String? version]) {
    // TODO: implement getCodeSystem
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>?> getResourceMap(String url) {
    // TODO: implement getResourceMap
    throw UnimplementedError();
  }

  @override
  Future<List<String>> getResourceNames() {
    // TODO: implement getResourceNames
    throw UnimplementedError();
  }

  @override
  Future<fhir.StructureDefinition?> getStructureDefinition(String url) {
    // TODO: implement getStructureDefinition
    throw UnimplementedError();
  }

  @override
  Future<List<fhir.StructureDefinition>> getStructureDefinitions() {
    // TODO: implement getStructureDefinitions
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
              'diagnostics': 'Request body is empty'
            }
          ]
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    dynamic requestJson;
    try {
      requestJson = jsonDecode(body);
    } catch (e) {
      return Response(
        400,
        body: jsonEncode({
          'resourceType': 'OperationOutcome',
          'issue': [
            {
              'severity': 'error',
              'code': 'invalid',
              'diagnostics': 'Invalid JSON format: ${e.toString()}'
            }
          ]
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
              'diagnostics': 'Missing required field: map (StructureMap)'
            }
          ]
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
              'diagnostics': 'Missing required field: source (source resource)'
            }
          ]
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Parse StructureMap
    fhir.StructureMap structureMap;
    try {
      structureMap = fhir.StructureMap.fromJson(requestJson['map']);
    } catch (e) {
      return Response(
        400,
        body: jsonEncode({
          'resourceType': 'OperationOutcome',
          'issue': [
            {
              'severity': 'error',
              'code': 'invalid',
              'diagnostics': 'Invalid StructureMap: ${e.toString()}'
            }
          ]
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
              'diagnostics': 'Invalid source resource: ${e.toString()}'
            }
          ]
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
      null, // target (null means create new)
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
              'diagnostics': 'Mapping returned null result'
            }
          ]
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    FhirantLogging().logInfo(
      'Resource transformation completed successfully',
    );

    // Convert FhirBase result back to JSON
    // FhirBase has toJson() method
    final resultJson = transformed.toJson();

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
            'diagnostics': 'Mapping error: ${e.toString()}'
          }
        ]
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
