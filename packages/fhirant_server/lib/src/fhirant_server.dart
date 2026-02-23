// lib/src/core/server_core.dart
import 'dart:async';
import 'dart:io';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/handlers.dart';
import 'package:fhirant_server/src/middlewares/audit_middleware.dart';
import 'package:fhirant_server/src/middlewares/auth_middleware.dart';
import 'package:fhirant_server/src/middlewares/content_negotiation.dart';
import 'package:fhirant_server/src/middlewares/cors_middleware.dart';
import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_rate_limiter/shelf_rate_limiter.dart';

/// A single logged HTTP request.
class RequestLogEntry {
  final DateTime timestamp;
  final String method;
  final String path;
  final int statusCode;
  final int durationMs;
  final String clientIp;

  RequestLogEntry({
    required this.timestamp,
    required this.method,
    required this.path,
    required this.statusCode,
    required this.durationMs,
    required this.clientIp,
  });
}

/// Core server functionality without platform-specific dependencies
class FhirAntServer {
  final FhirAntDb dbInterface;
  final String exportDir;
  final int maxRequests;
  final Duration rateLimitDuration;
  late final JwtService _jwtService;
  HttpServer? _server;
  bool _isRunning = false;
  final StreamController<RequestLogEntry> _requestLogController =
      StreamController<RequestLogEntry>.broadcast();

  FhirAntServer(
    this.dbInterface, {
    String? jwtSecret,
    String? exportDir,
    this.maxRequests = 10,
    this.rateLimitDuration = const Duration(seconds: 60),
  }) : exportDir = exportDir ?? 'data/export' {
    final secret = jwtSecret ??
        Platform.environment['FHIRANT_JWT_SECRET'] ??
        'fhirant-dev-secret-change-in-production';
    _jwtService = JwtService(secret);
  }

  bool get isRunning => _isRunning;
  int? get port => _server?.port;

  /// Stream of request log entries for live monitoring.
  Stream<RequestLogEntry> get requestLog => _requestLogController.stream;

  /// Create router with all handlers
  Router createRouter() {
    final router = Router()
      // Auth routes
      ..post('/auth/register',
          (Request req) => registerHandler(req, dbInterface))
      ..post('/auth/login',
          (Request req) => loginHandler(req, dbInterface, _jwtService))
      // Public routes
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
      // Bulk Data Export endpoints
      ..get(
        '/\$export',
        (Request req) => exportKickoffHandler(
            req, dbInterface, exportDir,
            exportLevel: 'system'),
      )
      ..get(
        '/Group/<groupId>/\$export',
        (Request req, String groupId) => exportKickoffHandler(
            req, dbInterface, exportDir,
            exportLevel: 'group', groupId: groupId),
      )
      ..get(
        '/Patient/\$export',
        (Request req) => exportKickoffHandler(
            req, dbInterface, exportDir,
            exportLevel: 'patient'),
      )
      ..get(
        '/\$export-poll-status/<jobId>',
        (Request req, String jobId) =>
            exportStatusHandler(req, dbInterface, jobId),
      )
      ..delete(
        '/\$export-poll-status/<jobId>',
        (Request req, String jobId) =>
            exportDeleteHandler(req, dbInterface, exportDir, jobId),
      )
      ..get(
        '/\$export-file/<jobId>/<fileName>',
        (Request req, String jobId, String fileName) =>
            exportFileHandler(req, exportDir, jobId, fileName),
      )
      // $everything operation (before history to avoid /<type>/<id>/_history match)
      ..get(
        r'/<compartmentType>/<id>/$everything',
        (Request req, String compartmentType, String id) =>
            everythingHandler(req, compartmentType, id, dbInterface),
      )
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
      // Compartment search (3-segment: /Patient/123/Observation)
      // Must come after _history routes so /<type>/<id>/_history matches first
      ..get(
        r'/<compartmentType>/<compartmentId>/<resourceType>',
        (Request req, String compartmentType, String compartmentId,
                String resourceType) =>
            compartmentSearchHandler(
                req, compartmentType, compartmentId, resourceType, dbInterface),
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
      )
      ..delete(
        '/<resourceType>',
        (Request req, String resourceType) =>
            conditionalDeleteHandler(req, resourceType, dbInterface),
      );


    return router;
  }

  /// Create pipeline with middleware
  Handler createHandler(Router router) {
    // Setup rate limiting
    final memoryStorage = MemStorage();
    final rateLimiter = ShelfRateLimiter(
      storage: memoryStorage,
      duration: rateLimitDuration,
      maxRequests: maxRequests,
    );

    return Pipeline()
        .addMiddleware(_logRequestsMiddleware())
        .addMiddleware(corsMiddleware())
        .addMiddleware(contentNegotiationMiddleware())
        .addMiddleware(authMiddleware(_jwtService))
        .addMiddleware(auditMiddleware(dbInterface))
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
    await _requestLogController.close();
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

        // Emit to the request log stream for live monitoring
        if (!_requestLogController.isClosed) {
          _requestLogController.add(RequestLogEntry(
            timestamp: startTime,
            method: request.method,
            path: request.requestedUri.path,
            statusCode: response.statusCode,
            durationMs: duration.inMilliseconds,
            clientIp: clientIp,
          ));
        }

        return response;
      };
    };
  }
}
