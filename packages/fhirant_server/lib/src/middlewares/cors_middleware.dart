import 'package:shelf/shelf.dart';

/// Configuration for CORS headers.
class CorsConfig {
  const CorsConfig({
    this.allowOrigin,
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
  /// Origin to allow, or null to emit no CORS headers at all.
  ///
  /// Null is the default, and it means browsers will not let a page read this
  /// server's responses. That is the safer starting point here: authentication
  /// is by bearer token rather than cookie, so a wide-open policy does not leak
  /// authenticated data by itself — but it does let any page the operator
  /// visits use their browser to reach a server on their local network that
  /// the page's author could not reach directly, and read what comes back.
  ///
  /// A browser-based client (a SMART app) needs this set to its origin, or to
  /// `*`. That is a deliberate choice an operator makes, not a default they
  /// inherit without knowing.
  final String? allowOrigin;
  final List<String> allowMethods;
  final List<String> allowHeaders;
  final List<String> exposeHeaders;
  final int maxAge;
}

/// Middleware that adds CORS headers to all responses and handles OPTIONS
/// preflight requests.
///
/// Place early in the pipeline (after logging, before content negotiation)
/// so that OPTIONS preflight is short-circuited before auth or format checks.
Middleware corsMiddleware({CorsConfig? config}) {
  final c = config ?? const CorsConfig();

  final allowOrigin = c.allowOrigin;
  if (allowOrigin == null) {
    // No cross-origin policy published. Preflight still gets a well-formed
    // answer — just one without permission in it.
    return (Handler innerHandler) {
      return (Request request) async {
        if (request.method == 'OPTIONS') return Response(204);
        return innerHandler(request);
      };
    };
  }

  final corsHeaders = {
    'access-control-allow-origin': allowOrigin,
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
