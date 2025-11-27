import 'dart:convert';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhir_r4_path/fhir_r4_path.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:shelf/shelf.dart';

/// FHIRPath Handler - Evaluate FHIRPath expressions against resources
Future<Response> fhirPathHandler(
  Request request,
  FuegoDbInterface dbInterface,
) async {
  try {
    FhirantLogging().logInfo('Received FHIRPath request');

    final queryParams = request.url.queryParameters;
    final expression = queryParams['expression'];
    final resourceType = queryParams['resourceType'];
    final resourceId = queryParams['resourceId'];

    if (expression == null || expression.isEmpty) {
      return Response(
        400,
        body: jsonEncode({
          'resourceType': 'OperationOutcome',
          'issue': [
            {
              'severity': 'error',
              'code': 'invalid',
              'diagnostics': 'Missing required parameter: expression'
            }
          ]
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    fhir.Resource? resource;

    // Try to get resource from query parameters first
    if (resourceType != null && resourceId != null) {
      final type = fhir.R4ResourceType.fromString(resourceType);
      if (type == null) {
        return Response(
          400,
          body: jsonEncode({
            'resourceType': 'OperationOutcome',
            'issue': [
              {
                'severity': 'error',
                'code': 'invalid',
                'diagnostics': 'Invalid resource type: $resourceType'
              }
            ]
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      resource = await dbInterface.getResource(type, resourceId);
      if (resource == null) {
        return Response(
          404,
          body: jsonEncode({
            'resourceType': 'OperationOutcome',
            'issue': [
              {
                'severity': 'error',
                'code': 'not-found',
                'diagnostics': 'Resource not found: $resourceType/$resourceId'
              }
            ]
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
    } else {
      // Try to get resource from request body
      final body = await request.readAsString();
      if (body.isNotEmpty) {
        try {
          resource = fhir.Resource.fromJsonString(body);
        } catch (e) {
          return Response(
            400,
            body: jsonEncode({
              'resourceType': 'OperationOutcome',
              'issue': [
                {
                  'severity': 'error',
                  'code': 'invalid',
                  'diagnostics': 'Invalid resource in request body: ${e.toString()}'
                }
              ]
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }
      }
    }

    if (resource == null) {
      return Response(
        400,
        body: jsonEncode({
          'resourceType': 'OperationOutcome',
          'issue': [
            {
              'severity': 'error',
              'code': 'invalid',
              'diagnostics':
                  'No resource provided. Use query params (resourceType & resourceId) or request body'
            }
          ]
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Evaluate FHIRPath expression using walkFhirPath (simpler API)
    final result = await walkFhirPath(
      context: resource,
      pathExpression: expression,
    );

    // Convert result to JSON
    final resultJson = result.map((e) => e.toJson()).toList();

    FhirantLogging().logInfo(
      'FHIRPath expression evaluated successfully: $expression',
    );

    // TODO: Add audit log entry for PHI access
    // await dbInterface.logAuditEvent(...);

    return Response.ok(
      jsonEncode(resultJson),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('FHIRPath evaluation failed', e, stackTrace);
    return Response(
      500,
      body: jsonEncode({
        'resourceType': 'OperationOutcome',
        'issue': [
          {
            'severity': 'error',
            'code': 'exception',
            'diagnostics': 'FHIRPath evaluation error: ${e.toString()}'
          }
        ]
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
