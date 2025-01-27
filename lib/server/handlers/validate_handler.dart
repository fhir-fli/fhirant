import 'dart:convert';
import 'package:fhir_r4/fhir_r4.dart';
import 'package:shelf/shelf.dart';

/// Validation Handler
Future<Response> validateHandler(Request request) async {
  try {
    // Read the request body
    final body = await request.readAsString();

    // Validate the FHIR resource
    final validationResults = await FhirValidator.validateFhirString(
      structureToValidate: body,
    );

    // Generate an OperationOutcome from the results
    final operationOutcome = validationResults.toOperationOutcome();

    // Determine the response based on the severity of results
    if (validationResults.hasErrors) {
      // Return 400 for errors
      return Response(
        400,
        body: operationOutcome.toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    } else {
      // Return 200 for valid or warnings
      return Response.ok(
        operationOutcome.toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    }
  } catch (e) {
    // Handle invalid input or unexpected exceptions
    return Response(
      400,
      body: jsonEncode({'error': 'Invalid request', 'message': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
