import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant/fhirant.dart';
import 'package:shelf/shelf.dart';

/// Handler to fetch all resources of a given type
Future<Response> getResourcesHandler(
  Request request,
  String resourceType,
  DbService dbService,
) async {
  try {
    FhirAntLoggingService().logInfo(
      'Fetching resources of type: $resourceType',
    );

    final queryParams = request.url.queryParameters;
    final count = int.tryParse(queryParams['_count'] ?? '20') ?? 20;
    final offset = int.tryParse(queryParams['_offset'] ?? '0') ?? 0;

    final type = R4ResourceType.fromString(resourceType);
    if (type == null) {
      FhirAntLoggingService().logWarning(
        'Invalid resource type requested: $resourceType',
      );
      return _validationErrorResponse('Invalid resource type');
    }

    final resources = await dbService.getResourcesWithPagination(
      resourceType: type,
      count: count,
      offset: offset,
    );

    final baseUrl =
        '${request.requestedUri.scheme}://${request.requestedUri.host}:${request.requestedUri.port}';
    final bundle = Bundle(
      type: BundleType.searchset,
      entry:
          resources
              .map(
                (resource) => BundleEntry(
                  resource: resource,
                  fullUrl: FhirUri('$baseUrl/$resourceType/${resource.id}'),
                ),
              )
              .toList(),
      total: FhirUnsignedInt(resources.length),
    );

    FhirAntLoggingService().logInfo(
      'Successfully fetched ${resources.length} '
      'resources of type: $resourceType',
    );
    return Response.ok(
      bundle.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirAntLoggingService().logError(
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
  DbService dbService,
) async {
  try {
    final body = await request.readAsString();
    final resource = Resource.fromJsonString(body);

    if (resource.resourceTypeString != resourceType) {
      FhirAntLoggingService().logWarning(
        'Resource type mismatch: expected $resourceType, '
        'got ${resource.resourceTypeString}',
      );
      return _validationErrorResponse(
        'Resource type in URL does not match resource type in body',
      );
    }

    final result = await dbService.saveResource(resource);
    if (result) {
      FhirAntLoggingService().logInfo(
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
      FhirAntLoggingService().logError(
        'Failed to save resource of type: $resourceType',
      );
      return _errorResponse(
        'Failed to save resource',
        'Database operation failed',
      );
    }
  } catch (e, stackTrace) {
    FhirAntLoggingService().logError(
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
  DbService dbService,
) async {
  try {
    final body = await request.readAsString();
    final updatedResource = Resource.fromJsonString(body);

    if (updatedResource.resourceTypeString != resourceType) {
      FhirAntLoggingService().logWarning(
        'Resource type mismatch in update: expected $resourceType, '
        'got ${updatedResource.resourceTypeString}',
      );
      return _validationErrorResponse(
        'Resource type in URL does not match resource type in body',
      );
    }

    if (updatedResource.id?.value != id) {
      FhirAntLoggingService().logWarning(
        'Resource ID mismatch in update: expected $id, '
        'got ${updatedResource.id?.value}',
      );
      return _validationErrorResponse(
        'Resource ID in URL does not match resource ID in body',
      );
    }

    final success = await dbService.saveResource(updatedResource);
    if (success) {
      FhirAntLoggingService().logInfo(
        'Resource of type $resourceType updated successfully with ID: $id',
      );
      return Response(
        200,
        body: updatedResource.toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    } else {
      FhirAntLoggingService().logError(
        'Failed to update resource of type: $resourceType with ID: $id',
      );
      return _errorResponse(
        'Failed to update resource',
        'Database operation failed',
      );
    }
  } catch (e, stackTrace) {
    FhirAntLoggingService().logError(
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
  DbService dbService,
) async {
  try {
    final type = R4ResourceType.fromString(resourceType);
    if (type == null) {
      FhirAntLoggingService().logWarning(
        'Invalid resource type requested: $resourceType',
      );
      return _validationErrorResponse('Invalid resource type');
    }

    final resource = await dbService.getResource(type, id);
    if (resource != null) {
      FhirAntLoggingService().logInfo(
        'Resource of type $resourceType with ID $id found.',
      );
      return Response.ok(
        resource.toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    } else {
      FhirAntLoggingService().logWarning(
        'Resource of type $resourceType with ID $id not found.',
      );
      return Response(
        404,
        body: jsonEncode({'error': 'Resource not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  } catch (e, stackTrace) {
    FhirAntLoggingService().logError(
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
  final operationOutcome = OperationOutcome(
    issue: [
      OperationOutcomeIssue(
        severity: IssueSeverity.error,
        code: IssueType.exception,
        diagnostics: '$message: $details'.toFhirString,
      ),
    ],
  );

  FhirAntLoggingService().logWarning('Error Response: $message - $details');
  return Response(
    statusCode,
    body: operationOutcome.toJsonString(),
    headers: {'Content-Type': 'application/json'},
  );
}

/// Utility for creating a validation error response
Response _validationErrorResponse(String message) {
  final operationOutcome = OperationOutcome(
    issue: [
      OperationOutcomeIssue(
        severity: IssueSeverity.error,
        code: IssueType.processing,
        diagnostics: message.toFhirString,
      ),
    ],
  );

  FhirAntLoggingService().logWarning('Validation Error: $message');
  return Response(
    400,
    body: operationOutcome.toJsonString(),
    headers: {'Content-Type': 'application/json'},
  );
}
