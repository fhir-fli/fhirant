import 'dart:convert';
import 'package:fhir_r4/fhir_r4.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';

final Logger _logger = Logger('ValidationHandler');

/// Validation Handler
Future<Response> validateHandler(Request request) async {
  try {
    _logger.info('Received validation request');
    
    // Read the request body
    final body = await request.readAsString();

    // Validate the FHIR resource
    final validationResults = await FhirValidator.validateFhirString(
      structureToValidate: body,
    );

    // Generate an OperationOutcome from the results
    final operationOutcome = validationResults.toOperationOutcome();

    if (validationResults.hasErrors) {
      _logger.warning('FHIR validation failed');
      return Response(
        400,
        body: operationOutcome.toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    } else {
      _logger.info('FHIR validation passed');
      return Response.ok(
        operationOutcome.toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    }
  } catch (e, stackTrace) {
    _logger.severe('Validation failed due to an exception', e, stackTrace);
    return Response(
      400,
      body: jsonEncode({'error': 'Invalid request', 'message': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
