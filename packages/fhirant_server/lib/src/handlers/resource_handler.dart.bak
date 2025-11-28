import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:shelf/shelf.dart';

/// Handler to fetch all resources of a given type
Future<Response> getResourcesHandler(
  Request request,
  String resourceType,
  FuegoDbInterface dbInterface,
) async {
  try {
    FhirantLogging().logInfo(
      'Fetching resources of type: $resourceType',
    );

    final queryParams = request.url.queryParameters;
    final count = int.tryParse(queryParams['_count'] ?? '20') ?? 20;
    final offset = int.tryParse(queryParams['_offset'] ?? '0') ?? 0;

    final type = fhir.R4ResourceType.fromString(resourceType);
    if (type == null) {
      FhirantLogging().logWarning(
        'Invalid resource type requested: $resourceType',
      );
      return _validationErrorResponse('Invalid resource type');
    }

    final resources = await dbInterface.getResourcesWithPagination(
      resourceType: type,
      count: count,
      offset: offset,
    );

    final baseUrl =
        '${request.requestedUri.scheme}://${request.requestedUri.host}:${request.requestedUri.port}';
    final bundle = fhir.Bundle(
      type: fhir.BundleType.searchset,
      entry: resources
          .map(
            (resource) => fhir.BundleEntry(
              resource: resource,
              fullUrl: fhir.FhirUri('$baseUrl/$resourceType/${resource.id}'),
            ),
          )
          .toList(),
      total: fhir.FhirUnsignedInt(resources.length),
    );

    FhirantLogging().logInfo(
      'Successfully fetched ${resources.length} '
      'resources of type: $resourceType',
    );
    return Response.ok(
      bundle.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Failed to fetch resources of type: $resourceType',
      e,
      stackTrace,
    );
    return _errorResponse('Failed to fetch resources', e.toString());
  }
}

/// Handler to create a resource of a given type
Future<Response> postResourceHandler(
  Request request,
  String resourceType,
  FuegoDbInterface dbInterface,
) async {
  try {
    final body = await request.readAsString();
    final resource = fhir.Resource.fromJsonString(body);

    if (resource.resourceTypeString != resourceType) {
      FhirantLogging().logWarning(
        'Resource type mismatch: expected $resourceType, '
        'got ${resource.resourceTypeString}',
      );
      return _validationErrorResponse(
        'Resource type in URL does not match resource type in body',
      );
    }

    final result = await dbInterface.saveResource(resource);
    if (result) {
      FhirantLogging().logInfo(
        'Resource of type $resourceType saved successfully with ID: '
        '${resource.id}',
      );
      return Response(
        201,
        body: resource.toJsonString(),
        headers: {
          'Content-Type': 'application/json',
          'Location': '/$resourceType/${resource.id}',
        },
      );
    } else {
      FhirantLogging().logError(
        'Failed to save resource of type: $resourceType',
      );
      return _errorResponse(
        'Failed to save resource',
        'Database operation failed',
      );
    }
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error processing request for resource type: $resourceType',
      e,
      stackTrace,
    );
    return _errorResponse(
      'Error processing request',
      e.toString(),
      statusCode: 400,
    );
  }
}

/// Handler to update a resource by its type and ID
Future<Response> putResourceHandler(
  Request request,
  String resourceType,
  String id,
  FuegoDbInterface dbInterface,
) async {
  try {
    final body = await request.readAsString();
    final updatedResource = fhir.Resource.fromJsonString(body);

    if (updatedResource.resourceTypeString != resourceType) {
      FhirantLogging().logWarning(
        'Resource type mismatch in update: expected $resourceType, '
        'got ${updatedResource.resourceTypeString}',
      );
      return _validationErrorResponse(
        'Resource type in URL does not match resource type in body',
      );
    }

    // Compare ID as string
    final resourceId = updatedResource.id?.toString() ?? '';
    if (resourceId != id) {
      FhirantLogging().logWarning(
        'Resource ID mismatch in update: expected $id, '
        'got $resourceId',
      );
      return _validationErrorResponse(
        'Resource ID in URL does not match resource ID in body',
      );
    }

    final success = await dbInterface.saveResource(updatedResource);
    if (success) {
      FhirantLogging().logInfo(
        'Resource of type $resourceType updated successfully with ID: $id',
      );
      return Response(
        200,
        body: updatedResource.toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    } else {
      FhirantLogging().logError(
        'Failed to update resource of type: $resourceType with ID: $id',
      );
      return _errorResponse(
        'Failed to update resource',
        'Database operation failed',
      );
    }
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error updating resource of type: $resourceType with ID: $id',
      e,
      stackTrace,
    );
    return _errorResponse('Error updating resource', e.toString());
  }
}

/// Handler to fetch a specific resource by its type and ID
Future<Response> getResourceByIdHandler(
  Request request,
  String resourceType,
  String id,
  FuegoDbInterface dbInterface,
) async {
  try {
    final type = fhir.R4ResourceType.fromString(resourceType);
    if (type == null) {
      FhirantLogging().logWarning(
        'Invalid resource type requested: $resourceType',
      );
      return _validationErrorResponse('Invalid resource type');
    }

    final resource = await dbInterface.getResource(type, id);
    if (resource != null) {
      FhirantLogging().logInfo(
        'Resource of type $resourceType with ID $id found.',
      );
      return Response.ok(
        resource.toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    } else {
      FhirantLogging().logWarning(
        'Resource of type $resourceType with ID $id not found.',
      );
      return Response(
        404,
        body: jsonEncode({'error': 'Resource not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error fetching resource of type: $resourceType with ID: $id',
      e,
      stackTrace,
    );
    return _errorResponse('Failed to fetch resource', e.toString());
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
