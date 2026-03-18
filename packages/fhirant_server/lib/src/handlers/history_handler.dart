import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/utils/http_headers.dart';
import 'package:shelf/shelf.dart';

/// Handler for resource-level history: GET /{resourceType}/{id}/_history
Future<Response> resourceHistoryHandler(
  Request request,
  String resourceType,
  String id,
  FhirAntDb dbInterface,
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

    // Get pagination and history parameters
    final queryParams = request.url.queryParameters;
    final count = int.tryParse(queryParams['_count'] ?? '20') ?? 20;
    final offset = int.tryParse(queryParams['_offset'] ?? '0') ?? 0;
    final since = _parseSince(queryParams['_since']);
    final at = _parseSince(queryParams['_at']);

    // _since and _at are mutually exclusive
    if (since != null && at != null) {
      return _validationErrorResponse(
        '_since and _at are mutually exclusive; specify only one',
      );
    }

    // Get history from database (with optional _since or _at filter)
    final history = await dbInterface.getResourceHistory(
      type, id, since: since, at: at,
    );

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
              final lastUpdated = resource.meta?.lastUpdated?.valueString;
              final tags = resource.meta?.tag;
              final isDeleted = tags != null &&
                  tags.any((t) => t.code?.valueString == 'DELETED');

              return fhir.BundleEntry(
                resource: isDeleted ? null : resource,
                fullUrl: fhir.FhirUri(
                  '$baseUrl/$resourceType/$id',
                ),
                request: fhir.BundleRequest(
                  method: isDeleted
                      ? fhir.HTTPVerb.dELETE
                      : fhir.HTTPVerb.gET,
                  url: fhir.FhirUri('$resourceType/$id'),
                ),
                response: fhir.BundleResponse(
                  status: isDeleted
                      ? '204'.toFhirString
                      : '200'.toFhirString,
                  etag: 'W/"$versionId"'.toFhirString,
                  lastModified: lastUpdated != null
                      ? fhir.FhirInstant.fromString(lastUpdated)
                      : null,
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
  FhirAntDb dbInterface,
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

    // Get pagination and history parameters
    final queryParams = request.url.queryParameters;
    final count = int.tryParse(queryParams['_count'] ?? '20') ?? 20;
    final offset = int.tryParse(queryParams['_offset'] ?? '0') ?? 0;
    final since = _parseSince(queryParams['_since']);
    final at = _parseSince(queryParams['_at']);

    // _since and _at are mutually exclusive
    if (since != null && at != null) {
      return _validationErrorResponse(
        '_since and _at are mutually exclusive; specify only one',
      );
    }

    // Query history table directly (no more N+1 queries)
    final allHistory = await dbInterface.getTypeHistory(
      type, since: since, at: at,
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
              final lastUpdated = resource.meta?.lastUpdated?.valueString;
              return fhir.BundleEntry(
                resource: resource,
                fullUrl: fhir.FhirUri(
                  '$baseUrl/$resourceTypeString/$resourceId',
                ),
                request: fhir.BundleRequest(
                  method: fhir.HTTPVerb.gET,
                  url: fhir.FhirUri(
                    '$resourceTypeString/$resourceId',
                  ),
                ),
                response: fhir.BundleResponse(
                  status: '200'.toFhirString,
                  etag: 'W/"$versionId"'.toFhirString,
                  lastModified: lastUpdated != null
                      ? fhir.FhirInstant.fromString(lastUpdated)
                      : null,
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
  FhirAntDb dbInterface,
) async {
  try {
    FhirantLogging().logInfo('Fetching system-level history');

    // Get pagination and history parameters
    final queryParams = request.url.queryParameters;
    final count = int.tryParse(queryParams['_count'] ?? '20') ?? 20;
    final offset = int.tryParse(queryParams['_offset'] ?? '0') ?? 0;
    final since = _parseSince(queryParams['_since']);
    final at = _parseSince(queryParams['_at']);

    // _since and _at are mutually exclusive
    if (since != null && at != null) {
      return _validationErrorResponse(
        '_since and _at are mutually exclusive; specify only one',
      );
    }

    // Query history table directly (no more N+1+1 queries)
    final allHistory = await dbInterface.getSystemHistory(
      since: since, at: at,
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
              final lastUpdated = resource.meta?.lastUpdated?.valueString;
              return fhir.BundleEntry(
                resource: resource,
                fullUrl: fhir.FhirUri(
                  '$baseUrl/$resourceTypeString/$resourceId',
                ),
                request: fhir.BundleRequest(
                  method: fhir.HTTPVerb.gET,
                  url: fhir.FhirUri(
                    '$resourceTypeString/$resourceId',
                  ),
                ),
                response: fhir.BundleResponse(
                  status: '200'.toFhirString,
                  etag: 'W/"$versionId"'.toFhirString,
                  lastModified: lastUpdated != null
                      ? fhir.FhirInstant.fromString(lastUpdated)
                      : null,
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
  FhirAntDb dbInterface,
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

    // Check if this version is a deletion tombstone
    final tags = versionedResource.meta?.tag;
    final isDeleted = tags != null &&
        tags.any((t) => t.code?.valueString == 'DELETED');
    if (isDeleted) {
      FhirantLogging().logInfo(
        'Version $vid of $resourceType/$id is a deletion tombstone (410)',
      );
      return Response(
        410,
        body: fhir.OperationOutcome(
          issue: [
            fhir.OperationOutcomeIssue(
              severity: fhir.IssueSeverity.error,
              code: fhir.IssueType.deleted,
              diagnostics:
                  'Resource $resourceType/$id version $vid has been deleted'
                      .toFhirString,
            ),
          ],
        ).toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    }

    FhirantLogging().logInfo(
      'Successfully fetched version $vid of resource: $resourceType/$id',
    );

    return Response.ok(
      versionedResource.toJsonString(),
      headers: FhirHttpHeaders.resourceHeaders(versionedResource),
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

/// Parse a FHIR instant/dateTime string into a [DateTime].
DateTime? _parseSince(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value);
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
