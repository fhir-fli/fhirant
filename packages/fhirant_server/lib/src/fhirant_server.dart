// lib/src/core/server_core.dart
import 'dart:io';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/handlers.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_rate_limiter/shelf_rate_limiter.dart';

/// Core server functionality without platform-specific dependencies
class FhirAntServer {
  final FhirAntDb dbInterface;
  HttpServer? _server;
  bool _isRunning = false;

  FhirAntServer(this.dbInterface);

  bool get isRunning => _isRunning;
  int? get port => _server?.port;

  /// Create router with all handlers
  Router createRouter() {
    final router = Router()
      ..get('/', baseHandler)
      ..get('/favicon.ico', favicoHandler)
      ..get('/metadata', metadataHandler)
      // Validation endpoints
      ..all(r'/$validate', (Request req) => validateHandler(req))
      ..all(
          r'/<resourceType>/$validate',
          (Request req, String resourceType) =>
              validateHandler(req, resourceType))
      // FHIRPath endpoint - supports GET and POST
      ..get('/\$fhirpath', (Request req) => fhirPathHandler(req, dbInterface))
      ..post('/\$fhirpath', (Request req) => fhirPathHandler(req, dbInterface))
      // Mapping/Transform endpoint
      ..post('/\$transform', mappingHandler)
      // History endpoints (must come before resource endpoints to match correctly)
      ..get(
        r'/<resourceType>/<id>/_history/<vid>',
        (Request req, String resourceType, String id, String vid) =>
            vreadResourceHandler(req, resourceType, id, vid, dbInterface),
      )
      ..get(
        r'/<resourceType>/<id>/_history',
        (Request req, String resourceType, String id) =>
            resourceHistoryHandler(req, resourceType, id, dbInterface),
      )
      ..get(
        r'/<resourceType>/_history',
        (Request req, String resourceType) =>
            typeHistoryHandler(req, resourceType, dbInterface),
      )
      ..get(
        r'/_history',
        (Request req) => systemHistoryHandler(req, dbInterface),
      )
      // Resource CRUD endpoints
      // Transaction/Batch endpoint
      ..post(
        '/',
        (Request req) => bundleHandler(req, dbInterface),
      )
      // Resource CRUD endpoints
      ..get(
        '/<resourceType>',
        (Request req, String resourceType) =>
            getResourcesHandler(req, resourceType, dbInterface),
      )
      ..post(
        '/<resourceType>',
        (Request req, String resourceType) =>
            postResourceHandler(req, resourceType, dbInterface),
      )
      ..get(
        '/<resourceType>/<id>',
        (Request req, String resourceType, String id) =>
            getResourceByIdHandler(req, resourceType, id, dbInterface),
      )
      ..put(
        '/<resourceType>/<id>',
        (Request req, String resourceType, String id) =>
            putResourceHandler(req, resourceType, id, dbInterface),
      )
      ..patch(
        '/<resourceType>/<id>',
        (Request req, String resourceType, String id) =>
            patchResourceHandler(req, resourceType, id, dbInterface),
      )
      ..delete(
        '/<resourceType>/<id>',
        (Request req, String resourceType, String id) =>
            deleteResourceHandler(req, resourceType, id, dbInterface),
      );


    return router;
  }

  /// Create pipeline with middleware
  Handler createHandler(Router router) {
    // Setup rate limiting
    final memoryStorage = MemStorage();
    final rateLimiter = ShelfRateLimiter(
      storage: memoryStorage,
      duration: const Duration(seconds: 60),
      maxRequests: 10,
    );

    return Pipeline()
        .addMiddleware(_logRequestsMiddleware())
        .addMiddleware(rateLimiter.rateLimiter())
        .addHandler(router);
  }

  /// Start the server with HTTP
  Future<void> startHttp(int port) async {
    if (_isRunning) return;

    final router = createRouter();
    final handler = createHandler(router);

    _server = await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4,
      port,
    );

    _isRunning = true;
    print(
        'Server started at http://${_server!.address.address}:${_server!.port}');
  }

  /// Start the server with HTTPS if cert/key available
  Future<void> startHttps(
      int port, String privateKeyPem, String certificatePem) async {
    if (_isRunning) return;

    final router = createRouter();
    final handler = createHandler(router);

    final securityContext = SecurityContext()
      ..useCertificateChainBytes(certificatePem.codeUnits)
      ..usePrivateKeyBytes(privateKeyPem.codeUnits);

    _server = await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4,
      port,
      securityContext: securityContext,
    );

    _isRunning = true;
    print(
        'Server started at https://${_server!.address.address}:${_server!.port}');
  }

  /// Stop the server
  Future<void> stop() async {
    if (!_isRunning) return;

    await _server!.close(force: true);
    _server = null;
    _isRunning = false;
    print('Server stopped');
  }

  /// Middleware for logging
  Middleware _logRequestsMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        final startTime = DateTime.now();
        final response = await innerHandler(request);
        final duration = DateTime.now().difference(startTime);

        final clientIp = request.headers['x-forwarded-for'] ??
            (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)
                ?.remoteAddress
                .address ??
            'Unknown';

        // Log the request using platform-agnostic logging
        print(
            '${request.method} ${request.requestedUri} - ${response.statusCode} (${duration.inMilliseconds}ms) from $clientIp');

        return response;
      };
    };
  }
}
