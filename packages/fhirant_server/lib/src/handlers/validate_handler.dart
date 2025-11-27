import 'dart:convert';
import 'package:fhir_r4_validation/fhir_r4_validation.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:shelf/shelf.dart';

/// Validation Handler with full fhir_r4_validation support
Future<Response> validateHandler(Request request,
    [String? resourceType]) async {
  try {
    FhirantLogging().logInfo('Received validation request');

    // Read the request body
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

    // Parse the resource to verify it's valid JSON
    dynamic resourceJson;
    try {
      resourceJson = jsonDecode(body);
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

    // Verify resource type if specified in URL
    if (resourceType != null) {
      final bodyResourceType = resourceJson['resourceType'];
      if (bodyResourceType != resourceType) {
        return Response(
          400,
          body: jsonEncode({
            'resourceType': 'OperationOutcome',
            'issue': [
              {
                'severity': 'error',
                'code': 'invalid',
                'diagnostics':
                    'Resource type in body ($bodyResourceType) does not match URL path ($resourceType)'
              }
            ]
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
    }

    // Use FhirValidationEngine for comprehensive validation
    final validator = FhirValidationEngine();
    final validationResults = await validator.validateFhirString(
      structureToValidate: body,
    );

    // Convert validation results to OperationOutcome
    final operationOutcome = validationResults.toOperationOutcome();

    if (validationResults.hasErrors) {
      final errorCount = validationResults.results
          .where((r) => r.severity == Severity.error)
          .length;
      FhirantLogging().logWarning(
        'FHIR validation failed with $errorCount errors',
      );
      return Response(
        400,
        body: operationOutcome.toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    } else {
      FhirantLogging().logInfo('FHIR validation passed');
      return Response.ok(
        operationOutcome.toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    }
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Validation failed due to an exception',
      e,
      stackTrace,
    );
    return Response(
      500,
      body: jsonEncode({
        'resourceType': 'OperationOutcome',
        'issue': [
          {
            'severity': 'error',
            'code': 'exception',
            'diagnostics': 'Validation error: ${e.toString()}'
          }
        ]
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
