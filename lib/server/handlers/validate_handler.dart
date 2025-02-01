import 'dart:convert';
import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant/fhirant.dart';
import 'package:shelf/shelf.dart';

/// Validation Handler
Future<Response> validateHandler(Request request) async {
  try {
    FhirAntLoggingService().logInfo('Received validation request');

    // Read the request body
    final body = await request.readAsString();

    // Validate the FHIR resource
    final validationResults = await FhirValidator.validateFhirString(
      structureToValidate: body,
    );

    // Generate an OperationOutcome from the results
    final operationOutcome = validationResults.toOperationOutcome();

    if (validationResults.hasErrors) {
      FhirAntLoggingService().logWarning('FHIR validation failed');
      return Response(
        400,
        body: operationOutcome.toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    } else {
      FhirAntLoggingService().logInfo('FHIR validation passed');
      return Response.ok(
        operationOutcome.toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    }
  } catch (e, stackTrace) {
    FhirAntLoggingService().logError(
      'Validation failed due to an exception',
      e,
      stackTrace,
    );
    return Response(
      400,
      body: jsonEncode({'error': 'Invalid request', 'message': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
