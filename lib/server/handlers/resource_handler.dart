import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant/db/db.dart';
import 'package:shelf/shelf.dart';

/// Handler to fetch all resources of a given type
Future<Response> getResourcesHandler(
  Request request,
  String resourceType,
) async {
  final dbService = DbService();
  try {
    // Parse query parameters
    final queryParams = request.url.queryParameters;

    // Extract pagination parameters
    final count = int.tryParse(queryParams['_count'] ?? '20') ?? 20;
    final offset = int.tryParse(queryParams['_offset'] ?? '0') ?? 0;

    // Fetch resources with pagination
    final resources = dbService.getResourcesWithPagination(
      resourceType: resourceType,
      count: count,
      offset: offset,
    );

    // Build the base URL dynamically from the request
    final baseUrl =
        '${request.requestedUri.scheme}://${request.requestedUri.host}:${request.requestedUri.port}';

    // Build FHIR Bundle
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

    return Response.ok(
      bundle.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return _errorResponse('Failed to fetch resources', e.toString());
  }
}

/// Handler to create a resource of a given type
Future<Response> postResourceHandler(
  Request request,
  String resourceType,
) async {
  try {
    final body = await request.readAsString();
    final resource = Resource.fromJsonString(body);

    if (resource.resourceTypeString != resourceType) {
      return _validationErrorResponse(
        'Resource type in URL does not match resource type in body',
      );
    }

    final result = DbService().saveResource(resource);

    if (result) {
      return Response(
        201,
        body: resource.toJsonString(),
        headers: {
          'Content-Type': 'application/json',
          'Location': '/$resourceType/${resource.id}',
        },
      );
    } else {
      return _errorResponse(
        'Failed to save resource',
        'Database operation failed',
      );
    }
  } catch (e) {
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
) async {
  try {
    final body = await request.readAsString();
    final updatedResource = Resource.fromJsonString(body);

    if (updatedResource.resourceTypeString != resourceType) {
      return _validationErrorResponse(
        'Resource type in URL does not match resource type in body',
      );
    }

    if (updatedResource.id?.value != id) {
      return _validationErrorResponse(
        'Resource ID in URL does not match resource ID in body',
      );
    }

    final success = DbService().saveResource(updatedResource);

    if (success) {
      return Response(
        200,
        body: updatedResource.toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    } else {
      return _errorResponse(
        'Failed to update resource',
        'Database operation failed',
      );
    }
  } catch (e) {
    return _errorResponse('Error updating resource', e.toString());
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

  return Response(
    400,
    body: operationOutcome.toJsonString(),
    headers: {'Content-Type': 'application/json'},
  );
}

/// Handler to fetch a specific resource by its type and ID
Future<Response> getResourceByIdHandler(
  Request request,
  String resourceType,
  String id,
) async {
  try {
    // Retrieve the resource from the database
    final resource = DbService().getResource(resourceType, id);

    if (resource != null) {
      // Resource found, return it
      return Response.ok(
        resource.toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    } else {
      // Resource not found, return an error
      final operationOutcome = OperationOutcome(
        issue: [
          OperationOutcomeIssue(
            severity: IssueSeverity.error,
            code: IssueType.not_found,
            diagnostics:
                'Resource of type $resourceType with ID $id not found.'
                    .toFhirString,
          ),
        ],
      );

      return Response(
        404,
        body: operationOutcome.toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    }
  } catch (e) {
    // Handle unexpected errors
    return _errorResponse('Failed to fetch resource', e.toString());
  }
}
