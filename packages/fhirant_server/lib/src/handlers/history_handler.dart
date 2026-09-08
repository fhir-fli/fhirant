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
    final total = await dbInterface.countHistory(
      type,
      id,
      since: since,
      at: at,
    );
    final paginatedHistory = total == 0
        ? const <HistoryEntry>[]
        : await dbInterface.getHistory(
            type,
            id,
            since: since,
            at: at,
            count: count,
            offset: offset,
          );

    if (total == 0) {
      FhirantLogging().logWarning(
        'No history found for resource: $resourceType/$id',
      );
      return Response(
        404,
        body: jsonEncode({'error': 'Resource not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Build base URL
    final baseUrl =
        '${request.requestedUri.scheme}://${request.requestedUri.host}:${request.requestedUri.port}';

    // Create Bundle with history entries
    final bundle = fhir.Bundle(
      type: fhir.BundleType.history,
      entry: [
        for (final e in paginatedHistory) _historyEntry(e, baseUrl),
      ],
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
      'Internal error',
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

    // The page and the total come from SQL (REVIEW-2026-09-06 finding 36).
    final total =
        await dbInterface.countTypeHistory(type, since: since, at: at);
    final paginatedHistory = await dbInterface.getTypeHistory(
      type,
      since: since,
      at: at,
      count: count,
      offset: offset,
    );

    // Build base URL
    final baseUrl =
        '${request.requestedUri.scheme}://${request.requestedUri.host}:${request.requestedUri.port}';

    // Create Bundle with history entries
    final bundle = fhir.Bundle(
      type: fhir.BundleType.history,
      entry: [
        for (final e in paginatedHistory) _historyEntry(e, baseUrl),
      ],
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
      'Internal error',
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

    // The page and the total come from SQL (REVIEW-2026-09-06 finding 36).
    final total = await dbInterface.countSystemHistory(since: since, at: at);
    final paginatedHistory = await dbInterface.getSystemHistory(
      since: since,
      at: at,
      count: count,
      offset: offset,
    );

    // Build base URL
    final baseUrl =
        '${request.requestedUri.scheme}://${request.requestedUri.host}:${request.requestedUri.port}';

    // Create Bundle with history entries
    final bundle = fhir.Bundle(
      type: fhir.BundleType.history,
      entry: [
        for (final e in paginatedHistory) _historyEntry(e, baseUrl),
      ],
      total: fhir.FhirUnsignedInt(total),
    );

    FhirantLogging().logInfo(
      'Successfully fetched ${paginatedHistory.length} '
      'system-level history entries',
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
      'Internal error',
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

    // One row by its key (REVIEW-2026-09-06 finding 36: every version used
    // to be read to find one).
    final entry = await dbInterface.getVersion(type, id, vid);
    if (entry == null) {
      final any = await dbInterface.countHistory(type, id);
      FhirantLogging().logWarning(
        any == 0
            ? 'No history found for resource: $resourceType/$id'
            : 'Version $vid not found for resource: $resourceType/$id',
      );
      return Response(
        404,
        body: jsonEncode({
          'error': any == 0 ? 'Resource not found' : 'Version not found',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // A deletion tombstone is 410, not a resource
    if (entry.deleted) {
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
    final versionedResource = entry.resource!;

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
      'Internal error',
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

/// One `Bundle.entry` of a history Bundle, the same for instance, type and
/// system history. R4B http.html "history" (read 2026-09-07): "Each entry
/// SHALL minimally contain at least one of: a resource which holds the
/// resource as it is at the conclusion of the interaction, or a request with
/// entry.request.method"; "If the entry.request.method is a PUT or a POST,
/// the entry SHALL contain a resource"; its delete example is an entry with
/// no resource, `method DELETE`, `url Patient/[id]` and a response
/// `lastModified`. A tombstone is that entry (status 204). Version 1 is the
/// create (`POST`, url `[type]`, 201); a later version an update (`PUT`,
/// url `[type]/[id]`, 200); under timestamp versioning the first version is
/// not told apart, and every version is a `PUT`, which http.html also
/// allows as a create ("Update as Create"). Type and system history used to
/// emit the tombstone JSON as a `GET` resource (REVIEW-2026-09-06 finding
/// 25).
fhir.BundleEntry _historyEntry(HistoryEntry e, String baseUrl) {
  final path = '${e.resourceType}/${e.id}';
  final isCreate = e.versionId == '1';
  return fhir.BundleEntry(
    resource: e.resource,
    fullUrl: fhir.FhirUri('$baseUrl/$path'),
    request: fhir.BundleRequest(
      method: e.deleted
          ? fhir.HTTPVerb.dELETE
          : isCreate
              ? fhir.HTTPVerb.pOST
              : fhir.HTTPVerb.pUT,
      url: fhir.FhirUri(isCreate && !e.deleted ? e.resourceType : path),
    ),
    response: fhir.BundleResponse(
      status: (e.deleted
              ? '204'
              : isCreate
                  ? '201'
                  : '200')
          .toFhirString,
      etag: 'W/"${e.versionId}"'.toFhirString,
      lastModified: fhir.FhirInstant.fromDateTime(e.lastUpdated),
    ),
  );
}
