import 'package:shelf/shelf.dart';

/// Middleware that handles FHIR content negotiation.
///
/// - Checks Accept header and _format parameter for supported types
/// - Returns 406 for unsupported formats (e.g., XML)
/// - Rewrites Content-Type from application/json to application/fhir+json
Middleware contentNegotiationMiddleware() {
  const supportedTypes = {
    'application/fhir+json',
    'application/json',
    'json',
    '*/*',
  };

  return (Handler innerHandler) {
    return (Request request) async {
      // Check _format parameter first (overrides Accept header)
      final format = request.url.queryParameters['_format'];
      final accept = request.headers['accept'] ?? '*/*';

      final requestedType = format ?? accept;

      // Check if any of the Accept types are supported
      // Accept can be comma-separated: "application/fhir+json, application/json"
      final types = requestedType
          .split(',')
          .map((t) => t.trim().split(';').first.trim());
      final isSupported = types.any((t) => supportedTypes.contains(t));

      if (!isSupported &&
          !types.contains('*/*') &&
          requestedType.isNotEmpty) {
        if (requestedType.contains('xml')) {
          return Response(
            406,
            body:
                '{"resourceType":"OperationOutcome","issue":[{"severity":"error","code":"not-supported","diagnostics":"XML format is not supported. Use application/fhir+json."}]}',
            headers: {
              'Content-Type': 'application/fhir+json; fhirVersion=4.0',
            },
          );
        }
        return Response(
          406,
          body:
              '{"resourceType":"OperationOutcome","issue":[{"severity":"error","code":"not-supported","diagnostics":"Unsupported format: $requestedType"}]}',
          headers: {
            'Content-Type': 'application/fhir+json; fhirVersion=4.0',
          },
        );
      }

      final response = await innerHandler(request);

      // Rewrite Content-Type for JSON responses
      final contentType = response.headers['content-type'] ?? '';
      if (contentType.contains('application/json')) {
        return response.change(headers: {
          'content-type': 'application/fhir+json; fhirVersion=4.0',
        });
      }

      return response;
    };
  };
}
