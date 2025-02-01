import 'dart:async';
import 'dart:io';

import 'package:fhirant/fhirant.dart';
import 'package:fhirant/server/handlers/favico_handler.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_rate_limiter/shelf_rate_limiter.dart';  
import 'package:shelf_router/shelf_router.dart' as shelf;

/// A singleton class to manage the server lifecycle and routing
class ServerManager {
  /// Factory constructor to return the singleton instance
  factory ServerManager() => _instance;

  /// Private constructor to enforce singleton pattern
  ServerManager._();

  /// Singleton instance
  static final ServerManager _instance = ServerManager._();

  HttpServer? _server; // Reference to the running server

  /// Getter to check if the server is running
  bool get isRunning => _server != null;

  /// Getter to return the server port
  int? get port => _server?.port;

  /// Database service instance
  final DbService _dbService = DbService();

  /// Start the server on the specified port
  Future<void> start({int port = 8080}) async {
    if (isRunning) {
      FhirAntLoggingService().logWarning('Server is already running.');
      return;
    }

    // Fetch certificates before starting
    final storageService = SecureStorageService();
    final privateKeyPem = await storageService.getPrivateKey();
    final certificatePem = await storageService.getCertificate();

    if (privateKeyPem == null || certificatePem == null) {
      FhirAntLoggingService().logError(
        'Missing certificates! Cannot start the server.',
      );
      return;
    }

    // Setup and start the server
    await _runServer(port, privateKeyPem, certificatePem);
  }

  /// Stop the server
  Future<void> stop() async {
    if (!isRunning) {
      FhirAntLoggingService().logWarning('Server is not running.');
      return;
    }

    FhirAntLoggingService().logInfo('Stopping server...');
    await _server!.close(force: true);
    _server = null;
    FhirAntLoggingService().logInfo('Server stopped.');
  }

  /// Runs the server in the main isolate
  Future<void> _runServer(
    int port,
    String? privateKeyPem,
    String? certificatePem,
  ) async {
    // Setup rate limiting
    final memoryStorage = MemStorage();  // In-memory storage for rate limiting
    final rateLimiter = ShelfRateLimiter(
      storage: memoryStorage,
      duration: const Duration(seconds: 60), // 60-second window
      maxRequests: 10, // 10 requests per minute
    );

    final router = shelf.Router()
      // ✅ Pass `_dbService` to each handler
      ..get('/', baseHandler)
      ..get('/favicon.ico', favicoHandler)
      ..post('/register', registerHandler)
      ..post('/login', loginHandler)
      ..get('/metadata', metadataHandler)
      ..all(r'/$validate', validateHandler)
      ..all(r'/<resourceType>/$validate', validateHandler)
      ..get(
        '/<resourceType>',
        (Request req, String resourceType) =>
            getResourcesHandler(req, resourceType, _dbService),
      )
      ..post(
        '/<resourceType>',
        (Request req, String resourceType) =>
            postResourceHandler(req, resourceType, _dbService),
      )
      ..get(
        '/<resourceType>/<id>',
        (Request req, String resourceType, String id) =>
            getResourceByIdHandler(req, resourceType, id, _dbService),
      )
      ..put(
        '/<resourceType>/<id>',
        (Request req, String resourceType, String id) =>
            putResourceHandler(req, resourceType, id, _dbService),
      );

    final handler = const Pipeline()
        .addMiddleware(_logRequestsMiddleware())
        .addMiddleware(authenticate())
        .addMiddleware(rateLimiter.rateLimiter())  // Add rate limiting here
        .addHandler(router.call);

    if (privateKeyPem == null || certificatePem == null) {
      FhirAntLoggingService().logWarning(
        'Certificates not found. Cannot start server.',
      );
      return;
    }

    final securityContext =
        SecurityContext()
          ..useCertificateChainBytes(certificatePem.codeUnits)
          ..usePrivateKeyBytes(privateKeyPem.codeUnits);

    _server = await serve(
      handler,
      InternetAddress.anyIPv4,
      port,
      securityContext: securityContext,
    );

    FhirAntLoggingService().logInfo(
      'Server started at https://${_server!.address.address}:${_server!.port}',
    );
  }

  /// **Middleware for structured logging**
  Middleware _logRequestsMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        final startTime = DateTime.now();
        final response = await innerHandler(request);
        final duration = DateTime.now().difference(startTime);

        final clientIp =
            request.headers['x-forwarded-for'] ??
            (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)
                ?.remoteAddress
                .address ??
            'Unknown';

        await _dbService.insertLog(
          level: 'INFO',
          message: 'Request received',
          method: request.method,
          url: request.requestedUri.toString(),
          statusCode: response.statusCode,
          responseTime: duration.inMilliseconds,
          clientIp: clientIp,
          user: request.context['authenticatedUser'] as String? ?? 'Anonymous',
        );

        return response;
      };
    };
  }
}
