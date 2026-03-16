// ignore_for_file: lines_longer_than_80_chars
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/utils/compartment_definitions.dart';
import 'package:fhirant_server/src/utils/search_parser.dart';
import 'package:shelf/shelf.dart';

/// Handler for `GET /<compartmentType>/<id>/$everything`.
///
/// Returns a searchset Bundle containing the focal resource plus all
/// resources linked to it via the compartment definition.
Future<Response> everythingHandler(
  Request request,
  String compartmentType,
  String id,
  FhirAntDb dbInterface,
) async {
  try {
    // 1. Validate compartment type
    final definition = CompartmentDefinitions.getDefinition(compartmentType);
    if (definition == null) {
      return _operationOutcome(
        400,
        'Unsupported compartment type: $compartmentType. '
            'Supported types: Patient, Encounter, Practitioner, RelatedPerson, Device',
      );
    }

    // 2. Fetch focal resource
    final focalType = fhir.R4ResourceType.fromString(compartmentType);
    if (focalType == null) {
      return _operationOutcome(400, 'Invalid resource type: $compartmentType');
    }
    final focalResource = await dbInterface.getResource(focalType, id);
    if (focalResource == null) {
      return _operationOutcome(
        404,
        '$compartmentType/$id not found',
      );
    }

    // 3. Parse optional parameters
    final queryParams = request.url.queryParameters;
    final typeFilterParam = queryParams['_type'];
    final sinceParam = queryParams['_since'];
    final countParam = queryParams['_count'];
    final offsetParam = queryParams['_offset'];

    final typeFilter =
        typeFilterParam?.split(',').map((s) => s.trim()).toList();
    DateTime? since;
    if (sinceParam != null) {
      since = DateTime.tryParse(sinceParam);
    }
    final count = int.tryParse(countParam ?? '') ?? 100;
    final offset = int.tryParse(offsetParam ?? '') ?? 0;

    // 4. Query compartment resource IDs
    final compartmentIds = await dbInterface.getCompartmentResourceIds(
      compartmentType: compartmentType,
      compartmentId: id,
      compartmentDefinition: definition,
      typeFilter: typeFilter,
      since: since,
    );

    // 5. Flatten to (type, id) pairs and fetch resources
    final allResources = <fhir.Resource>[focalResource];

    for (final entry in compartmentIds.entries) {
      final resTypeEnum = fhir.R4ResourceType.fromString(entry.key);
      if (resTypeEnum == null) continue;
      for (final resId in entry.value) {
        final resource = await dbInterface.getResource(resTypeEnum, resId);
        if (resource != null) {
          allResources.add(resource);
        }
      }
    }

    // 6. Paginate
    final total = allResources.length;
    final paged = allResources.skip(offset).take(count).toList();

    // 7. Build Bundle
    final baseUrl = _baseUrl(request);

    if (paged.isEmpty) {
      final bundle = fhir.Bundle(
        type: fhir.BundleType.searchset,
        total: fhir.FhirUnsignedInt(total),
      );
      return Response.ok(
        bundle.toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final entries = paged.map((resource) {
      final resType = resource.resourceTypeString;
      final resId = resource.id?.toString() ?? '';
      return fhir.BundleEntry(
        resource: resource,
        fullUrl: resId.isNotEmpty
            ? fhir.FhirUri('$baseUrl/$resType/$resId')
            : null,
      );
    }).toList();

    final bundle = fhir.Bundle(
      type: fhir.BundleType.searchset,
      total: fhir.FhirUnsignedInt(total),
      entry: entries,
    );

    FhirantLogging().logInfo(
      '\$everything for $compartmentType/$id returned $total resources',
    );

    return Response.ok(
      bundle.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error in \$everything for $compartmentType/$id',
      e,
      stackTrace,
    );
    return _operationOutcome(500, 'Internal error: $e');
  }
}

/// Handler for `GET /<compartmentType>/<compartmentId>/<resourceType>`.
///
/// Returns a searchset Bundle of resources of the given type that belong
/// to the specified compartment, optionally filtered by additional search
/// parameters.
Future<Response> compartmentSearchHandler(
  Request request,
  String compartmentType,
  String compartmentId,
  String resourceType,
  FhirAntDb dbInterface,
) async {
  try {
    // 1. Validate compartment type
    final definition = CompartmentDefinitions.getDefinition(compartmentType);
    if (definition == null) {
      return _operationOutcome(
        404,
        'Unsupported compartment type: $compartmentType',
      );
    }

    // 2. Validate resource type
    final resTypeEnum = fhir.R4ResourceType.fromString(resourceType);
    if (resTypeEnum == null) {
      return _operationOutcome(400, 'Invalid resource type: $resourceType');
    }

    // 3. Validate resource type is in compartment
    if (!definition.containsKey(resourceType)) {
      return _operationOutcome(
        400,
        '$resourceType is not part of the $compartmentType compartment',
      );
    }

    // 4. Verify focal resource exists
    final focalType = fhir.R4ResourceType.fromString(compartmentType);
    if (focalType == null) {
      return _operationOutcome(400, 'Invalid compartment type: $compartmentType');
    }
    final focalResource =
        await dbInterface.getResource(focalType, compartmentId);
    if (focalResource == null) {
      return _operationOutcome(
        404,
        '$compartmentType/$compartmentId not found',
      );
    }

    // 5. Get compartment resource IDs for this single type
    final searchPaths = definition[resourceType]!;

    Set<String> compartmentResourceIds;
    if (searchPaths.isEmpty) {
      // Focal resource type — just return the focal resource itself
      compartmentResourceIds = {compartmentId};
    } else {
      final compartmentIds = await dbInterface.getCompartmentResourceIds(
        compartmentType: compartmentType,
        compartmentId: compartmentId,
        compartmentDefinition: {resourceType: searchPaths},
      );
      compartmentResourceIds = compartmentIds[resourceType] ?? {};
    }

    // 6. Parse query parameters for additional search filters
    final queryParams = request.url.queryParameters;
    final parsed = SearchParameterParser.parseQueryParameters(queryParams);
    final searchParams = parsed['searchParams'] as Map<String, List<String>>?;
    final count = parsed['count'] as int? ?? 20;
    final offset = parsed['offset'] as int? ?? 0;
    final sort = parsed['sort'] as List<String>?;

    List<fhir.Resource> results;

    if (compartmentResourceIds.isEmpty) {
      results = [];
    } else if (searchParams != null && searchParams.isNotEmpty) {
      // Combine compartment IDs as _id constraint with additional search
      final combined = Map<String, List<String>>.from(searchParams);
      combined['_id'] = compartmentResourceIds.toList();
      results = await dbInterface.search(
        resourceType: resTypeEnum,
        searchParameters: combined,
        count: count,
        offset: offset,
        sort: sort,
      );
    } else {
      // No additional filters — fetch compartment resources directly
      results = [];
      for (final resId in compartmentResourceIds) {
        final resource = await dbInterface.getResource(resTypeEnum, resId);
        if (resource != null) {
          results.add(resource);
        }
      }
      // Apply pagination manually
      final total = results.length;
      results = results.skip(offset).take(count).toList();
      // We need total for bundle; recalculate after pagination
      return _buildSearchsetBundle(request, results, total);
    }

    final total = compartmentResourceIds.length;
    return _buildSearchsetBundle(request, results, total);
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error in compartment search $compartmentType/$compartmentId/$resourceType',
      e,
      stackTrace,
    );
    return _operationOutcome(500, 'Internal error: $e');
  }
}

/// Builds a searchset Bundle response.
Response _buildSearchsetBundle(
  Request request,
  List<fhir.Resource> resources,
  int total,
) {
  if (resources.isEmpty) {
    final bundle = fhir.Bundle(
      type: fhir.BundleType.searchset,
      total: fhir.FhirUnsignedInt(total),
    );
    return Response.ok(
      bundle.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  }

  final baseUrl = _baseUrl(request);
  final entries = resources.map((resource) {
    final resType = resource.resourceTypeString;
    final resId = resource.id?.toString() ?? '';
    return fhir.BundleEntry(
      resource: resource,
      fullUrl:
          resId.isNotEmpty ? fhir.FhirUri('$baseUrl/$resType/$resId') : null,
    );
  }).toList();

  final bundle = fhir.Bundle(
    type: fhir.BundleType.searchset,
    total: fhir.FhirUnsignedInt(total),
    entry: entries,
  );

  return Response.ok(
    bundle.toJsonString(),
    headers: {'Content-Type': 'application/json'},
  );
}

/// Extracts the base URL from a request.
String _baseUrl(Request request) {
  final uri = request.requestedUri;
  return uri.hasPort
      ? '${uri.scheme}://${uri.host}:${uri.port}'
      : '${uri.scheme}://${uri.host}';
}

/// Returns an OperationOutcome response.
Response _operationOutcome(int statusCode, String message) {
  final outcome = fhir.OperationOutcome(
    issue: [
      fhir.OperationOutcomeIssue(
        severity: statusCode >= 500
            ? fhir.IssueSeverity.fatal
            : fhir.IssueSeverity.error,
        code: statusCode == 404
            ? fhir.IssueType.notFound
            : fhir.IssueType.processing,
        diagnostics: message.toFhirString,
      ),
    ],
  );
  return Response(
    statusCode,
    body: outcome.toJsonString(),
    headers: {'Content-Type': 'application/json'},
  );
}
