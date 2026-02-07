import 'package:shelf/shelf.dart';

/// Configuration for CORS headers.
class CorsConfig {
  final String allowOrigin;
  final List<String> allowMethods;
  final List<String> allowHeaders;
  final List<String> exposeHeaders;
  final int maxAge;

  const CorsConfig({
    this.allowOrigin = '*',
    this.allowMethods = const [
      'GET',
      'POST',
      'PUT',
      'PATCH',
      'DELETE',
      'OPTIONS',
    ],
    this.allowHeaders = const [
      'Authorization',
      'Content-Type',
      'Accept',
      'Prefer',
      'If-Match',
      'If-None-Exist',
      'If-None-Match',
      'If-Modified-Since',
    ],
    this.exposeHeaders = const [
      'Content-Location',
      'ETag',
      'Last-Modified',
      'Location',
    ],
    this.maxAge = 86400,
  });
}

/// Middleware that adds CORS headers to all responses and handles OPTIONS
/// preflight requests.
///
/// Place early in the pipeline (after logging, before content negotiation)
/// so that OPTIONS preflight is short-circuited before auth or format checks.
Middleware corsMiddleware({CorsConfig? config}) {
  final c = config ?? const CorsConfig();

  final corsHeaders = {
    'access-control-allow-origin': c.allowOrigin,
    'access-control-allow-methods': c.allowMethods.join(', '),
    'access-control-allow-headers': c.allowHeaders.join(', '),
    'access-control-expose-headers': c.exposeHeaders.join(', '),
    'access-control-max-age': '${c.maxAge}',
  };

  return (Handler innerHandler) {
    return (Request request) async {
      // Preflight: return 204 immediately with CORS headers
      if (request.method == 'OPTIONS') {
        return Response(204, headers: corsHeaders);
      }

      final response = await innerHandler(request);
      return response.change(headers: corsHeaders);
    };
  };
}
