import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:shelf/shelf.dart';

/// Handler for resource-level history: GET /{resourceType}/{id}/_history
Future<Response> resourceHistoryHandler(
  Request request,
  String resourceType,
  String id,
  FuegoDbInterface dbInterface,
) async {
  try {
    FhirantLogging().logInfo(
      'Fetching history for resource: $resourceType/$id',
    );

    final type = fhir.R4ResourceType.fromString(resourceType);
    if (type == null) {
      FhirantLogging().logWarning(
        'Invalid resource type requested: $resourceType',
      );
      return _validationErrorResponse('Invalid resource type');
    }

    // Get pagination parameters
    final queryParams = request.url.queryParameters;
    final count = int.tryParse(queryParams['_count'] ?? '20') ?? 20;
    final offset = int.tryParse(queryParams['_offset'] ?? '0') ?? 0;

    // Get history from database
    final history = await dbInterface.getResourceHistory(type, id);

    if (history.isEmpty) {
      FhirantLogging().logWarning(
        'No history found for resource: $resourceType/$id',
      );
      return Response(
        404,
        body: jsonEncode({'error': 'Resource not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Apply pagination
    final total = history.length;
    final paginatedHistory = history.skip(offset).take(count).toList();

    // Build base URL
    final baseUrl =
        '${request.requestedUri.scheme}://${request.requestedUri.host}:${request.requestedUri.port}';

    // Create Bundle with history entries
    final bundle = fhir.Bundle(
      type: fhir.BundleType.history,
      entry: paginatedHistory
          .map(
            (resource) {
              final versionId = resource.meta?.versionId?.toString() ?? '1';
              return fhir.BundleEntry(
                resource: resource,
                fullUrl: fhir.FhirUri(
                  '$baseUrl/$resourceType/$id/_history/$versionId',
                ),
                request: fhir.BundleRequest(
                  method: fhir.HTTPVerb.gET,
                  url: fhir.FhirUri('$resourceType/$id/_history/$versionId'),
                ),
              );
            },
          )
          .toList(),
      total: fhir.FhirUnsignedInt(total),
    );

    FhirantLogging().logInfo(
      'Successfully fetched ${paginatedHistory.length} history entries '
      'for resource: $resourceType/$id',
    );

    return Response.ok(
      bundle.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error fetching history for resource: $resourceType/$id',
      e,
      stackTrace,
    );
    return _errorResponse(
      'Failed to fetch resource history',
      e.toString(),
    );
  }
}

/// Handler for type-level history: GET /{resourceType}/_history
Future<Response> typeHistoryHandler(
  Request request,
  String resourceType,
  FuegoDbInterface dbInterface,
) async {
  try {
    FhirantLogging().logInfo(
      'Fetching history for resource type: $resourceType',
    );

    final type = fhir.R4ResourceType.fromString(resourceType);
    if (type == null) {
      FhirantLogging().logWarning(
        'Invalid resource type requested: $resourceType',
      );
      return _validationErrorResponse('Invalid resource type');
    }

    // Get pagination parameters
    final queryParams = request.url.queryParameters;
    final count = int.tryParse(queryParams['_count'] ?? '20') ?? 20;
    final offset = int.tryParse(queryParams['_offset'] ?? '0') ?? 0;

    // Get all resources of this type
    final resources = await dbInterface.getResourcesByType(type);

    // Get history for all resources of this type
    final allHistory = <fhir.Resource>[];
    for (final resource in resources) {
      final resourceId = resource.id?.toString() ?? '';
      if (resourceId.isNotEmpty) {
        final history = await dbInterface.getResourceHistory(type, resourceId);
        allHistory.addAll(history);
      }
    }

    // Sort by lastUpdated descending (most recent first)
    allHistory.sort(
      (a, b) {
        final aDate = a.meta?.lastUpdated?.valueDateTime;
        final bDate = b.meta?.lastUpdated?.valueDateTime;
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      },
    );

    // Apply pagination
    final total = allHistory.length;
    final paginatedHistory = allHistory.skip(offset).take(count).toList();

    // Build base URL
    final baseUrl =
        '${request.requestedUri.scheme}://${request.requestedUri.host}:${request.requestedUri.port}';

    // Create Bundle with history entries
    final bundle = fhir.Bundle(
      type: fhir.BundleType.history,
      entry: paginatedHistory
          .map(
            (resource) {
              final resourceTypeString = resource.resourceTypeString;
              final resourceId = resource.id?.toString() ?? '';
              final versionId = resource.meta?.versionId?.toString() ?? '1';
              return fhir.BundleEntry(
                resource: resource,
                fullUrl: fhir.FhirUri(
                  '$baseUrl/$resourceTypeString/$resourceId/_history/$versionId',
                ),
                request: fhir.BundleRequest(
                  method: fhir.HTTPVerb.gET,
                  url: fhir.FhirUri(
                    '$resourceTypeString/$resourceId/_history/$versionId',
                  ),
                ),
              );
            },
          )
          .toList(),
      total: fhir.FhirUnsignedInt(total),
    );

    FhirantLogging().logInfo(
      'Successfully fetched ${paginatedHistory.length} history entries '
      'for resource type: $resourceType',
    );

    return Response.ok(
      bundle.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error fetching history for resource type: $resourceType',
      e,
      stackTrace,
    );
    return _errorResponse(
      'Failed to fetch resource type history',
      e.toString(),
    );
  }
}

/// Handler for system-level history: GET /_history
Future<Response> systemHistoryHandler(
  Request request,
  FuegoDbInterface dbInterface,
) async {
  try {
    FhirantLogging().logInfo('Fetching system-level history');

    // Get pagination parameters
    final queryParams = request.url.queryParameters;
    final count = int.tryParse(queryParams['_count'] ?? '20') ?? 20;
    final offset = int.tryParse(queryParams['_offset'] ?? '0') ?? 0;

    // Get all resource types
    final resourceTypes = await dbInterface.getResourceTypes();

    // Get history for all resources
    final allHistory = <fhir.Resource>[];
    for (final resourceType in resourceTypes) {
      final resources = await dbInterface.getResourcesByType(resourceType);
      for (final resource in resources) {
        final resourceId = resource.id?.toString() ?? '';
        if (resourceId.isNotEmpty) {
          final history =
              await dbInterface.getResourceHistory(resourceType, resourceId);
          allHistory.addAll(history);
        }
      }
    }

    // Sort by lastUpdated descending (most recent first)
    allHistory.sort(
      (a, b) {
        final aDate = a.meta?.lastUpdated?.valueDateTime;
        final bDate = b.meta?.lastUpdated?.valueDateTime;
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      },
    );

    // Apply pagination
    final total = allHistory.length;
    final paginatedHistory = allHistory.skip(offset).take(count).toList();

    // Build base URL
    final baseUrl =
        '${request.requestedUri.scheme}://${request.requestedUri.host}:${request.requestedUri.port}';

    // Create Bundle with history entries
    final bundle = fhir.Bundle(
      type: fhir.BundleType.history,
      entry: paginatedHistory
          .map(
            (resource) {
              final resourceTypeString = resource.resourceTypeString;
              final resourceId = resource.id?.toString() ?? '';
              final versionId = resource.meta?.versionId?.toString() ?? '1';
              return fhir.BundleEntry(
                resource: resource,
                fullUrl: fhir.FhirUri(
                  '$baseUrl/$resourceTypeString/$resourceId/_history/$versionId',
                ),
                request: fhir.BundleRequest(
                  method: fhir.HTTPVerb.gET,
                  url: fhir.FhirUri(
                    '$resourceTypeString/$resourceId/_history/$versionId',
                  ),
                ),
              );
            },
          )
          .toList(),
      total: fhir.FhirUnsignedInt(total),
    );

    FhirantLogging().logInfo(
      'Successfully fetched ${paginatedHistory.length} system-level history entries',
    );

    return Response.ok(
      bundle.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error fetching system-level history',
      e,
      stackTrace,
    );
    return _errorResponse(
      'Failed to fetch system history',
      e.toString(),
    );
  }
}

/// Handler for version-specific read (VRead): GET /{resourceType}/{id}/_history/{vid}
Future<Response> vreadResourceHandler(
  Request request,
  String resourceType,
  String id,
  String vid,
  FuegoDbInterface dbInterface,
) async {
  try {
    FhirantLogging().logInfo(
      'Fetching version $vid of resource: $resourceType/$id',
    );

    final type = fhir.R4ResourceType.fromString(resourceType);
    if (type == null) {
      FhirantLogging().logWarning(
        'Invalid resource type requested: $resourceType',
      );
      return _validationErrorResponse('Invalid resource type');
    }

    // Get history for this resource
    final history = await dbInterface.getResourceHistory(type, id);

    if (history.isEmpty) {
      FhirantLogging().logWarning(
        'No history found for resource: $resourceType/$id',
      );
      return Response(
        404,
        body: jsonEncode({'error': 'Resource not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Find the specific version
    fhir.Resource? versionedResource;
    for (final resource in history) {
      final versionId = resource.meta?.versionId?.toString() ?? '1';
      if (versionId == vid) {
        versionedResource = resource;
        break;
      }
    }

    if (versionedResource == null) {
      FhirantLogging().logWarning(
        'Version $vid not found for resource: $resourceType/$id',
      );
      return Response(
        404,
        body: jsonEncode({'error': 'Version not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    FhirantLogging().logInfo(
      'Successfully fetched version $vid of resource: $resourceType/$id',
    );

    return Response.ok(
      versionedResource.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error fetching version $vid of resource: $resourceType/$id',
      e,
      stackTrace,
    );
    return _errorResponse(
      'Failed to fetch resource version',
      e.toString(),
    );
  }
}

/// Utility for creating a generic error response
Response _errorResponse(
  String message,
  String details, {
  int statusCode = 500,
}) {
  final operationOutcome = fhir.OperationOutcome(
    issue: [
      fhir.OperationOutcomeIssue(
        severity: fhir.IssueSeverity.error,
        code: fhir.IssueType.exception,
        diagnostics: '$message: $details'.toFhirString,
      ),
    ],
  );

  FhirantLogging().logWarning('Error Response: $message - $details');
  return Response(
    statusCode,
    body: operationOutcome.toJsonString(),
    headers: {'Content-Type': 'application/json'},
  );
}

/// Utility for creating a validation error response
Response _validationErrorResponse(String message) {
  final operationOutcome = fhir.OperationOutcome(
    issue: [
      fhir.OperationOutcomeIssue(
        severity: fhir.IssueSeverity.error,
        code: fhir.IssueType.processing,
        diagnostics: message.toFhirString,
      ),
    ],
  );

  FhirantLogging().logWarning('Validation Error: $message');
  return Response(
    400,
    body: operationOutcome.toJsonString(),
    headers: {'Content-Type': 'application/json'},
  );
}
