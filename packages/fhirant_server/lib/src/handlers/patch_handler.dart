import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/utils/http_headers.dart';
import 'package:fhirant_server/src/utils/json_patch.dart';
import 'package:fhirant_server/src/utils/patient_scope.dart';
import 'package:shelf/shelf.dart';

/// Handler for PATCH operation: PATCH /{resourceType}/{id}
/// Supports JSON Patch (RFC 6902)
Future<Response> patchResourceHandler(
  Request request,
  String resourceType,
  String id,
  FhirAntDb dbInterface,
) async {
  try {
    FhirantLogging().logInfo(
      'Patching resource: $resourceType/$id',
    );

    final type = fhir.R4ResourceType.fromString(resourceType);
    if (type == null) {
      FhirantLogging().logWarning(
        'Invalid resource type requested: $resourceType',
      );
      return _validationErrorResponse('Invalid resource type');
    }

    // Get the current resource
    final currentResource = await dbInterface.getResource(type, id);
    if (currentResource == null) {
      FhirantLogging().logWarning(
        'Resource not found for PATCH: $resourceType/$id',
      );
      return Response(
        404,
        body: jsonEncode({'error': 'Resource not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Patient-level scope enforcement for patch
    final patchPatientId = extractPatientContext(request);
    if (patchPatientId != null) {
      if (!await isInPatientCompartment(
          resourceType, id, patchPatientId, dbInterface)) {
        return patientScopeForbiddenResponse(
            resourceType, id, patchPatientId);
      }
    }

    // Read and parse the patch document
    final body = await request.readAsString();
    List<dynamic> patchOperations;
    try {
      final patchDoc = jsonDecode(body) as dynamic;
      if (patchDoc is List) {
        patchOperations = patchDoc;
      } else if (patchDoc is Map && patchDoc['resourceType'] == 'Parameters') {
        // FHIR Patch format - convert to JSON Patch
        patchOperations = convertFhirPatchToJsonPatch(patchDoc);
      } else {
        return _validationErrorResponse(
          'Invalid patch format. Expected JSON Patch array or FHIR Parameters resource.',
        );
      }
    } catch (e) {
      FhirantLogging().logError('Error parsing patch document: $e');
      return _validationErrorResponse('Invalid JSON in patch document: $e');
    }

    // Convert resource to JSON for patching
    final resourceJson = currentResource.toJson();

    // Apply patch operations
    try {
      final patchedJson = applyJsonPatch(resourceJson, patchOperations);

      // Convert back to resource
      final patchedResource = fhir.Resource.fromJson(patchedJson);

      // Validate resource type and ID haven't changed
      if (patchedResource.resourceTypeString != resourceType) {
        return _validationErrorResponse(
          'Patch operation cannot change resource type',
        );
      }

      final resourceId = patchedResource.id?.toString() ?? '';
      if (resourceId != id) {
        return _validationErrorResponse(
          'Patch operation cannot change resource ID',
        );
      }

      // Save the patched resource (creates new version automatically)
      final success = await dbInterface.saveResource(patchedResource);
      if (!success) {
        FhirantLogging().logError(
          'Failed to save patched resource: $resourceType/$id',
        );
        return _errorResponse(
          'Failed to save patched resource',
          'Database operation failed',
        );
      }

      // Re-fetch to get server-assigned version/lastUpdated
      final savedResource =
          await dbInterface.getResource(type, id);
      final responseResource = savedResource ?? patchedResource;

      FhirantLogging().logInfo(
        'Successfully patched resource: $resourceType/$id',
      );

      final preference =
          FhirHttpHeaders.parsePreferReturn(request.headers);
      return FhirHttpHeaders.preferredResponse(
        statusCode: 200,
        resource: responseResource,
        headers: FhirHttpHeaders.resourceHeaders(responseResource),
        preference: preference,
      );
    } catch (e, stackTrace) {
      FhirantLogging().logError(
        'Error applying patch to resource: $resourceType/$id',
        e,
        stackTrace,
      );
      return _errorResponse(
        'Failed to apply patch',
        e.toString(),
        statusCode: 400,
      );
    }
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error processing PATCH request for: $resourceType/$id',
      e,
      stackTrace,
    );
    return _errorResponse(
      'Error processing PATCH request',
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
