import 'dart:async';
import 'dart:io';

import 'package:fhirant/fhirant.dart';
import 'package:fhirant/server/handlers/favico_handler.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
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
  final shelf.Router _router = shelf.Router(); // Router instance for routes

  final Logger _logger = Logger('ServerManager');

  /// Getter to check if the server is running
  bool get isRunning => _server != null;

  /// Getter to return the server port
  int? get port => _server?.port;

  /// Database service for structured logging
  final _dbService = DbService();

  /// Starts the server directly in the main isolate
  Future<void> start({int port = 8080}) async {
    if (isRunning) {
      _logger.warning('Server is already running.');
      await _dbService.insertLog(
        level: 'WARNING',
        message: 'Server already running',
      );
      return;
    }

    try {
      LoggingService.initialize(); // ✅ Initialize logging
      _logger.info('Initializing routes...');
      await _dbService.insertLog(
        level: 'INFO',
        message: 'Initializing routes...',
      );
      _initializeRoutes();

      // Add middleware and assign the router as the handler
      final handler = const Pipeline()
          .addMiddleware(
            _logRequestsMiddleware(),
          ) // ✅ Structured logging middleware
          .addMiddleware(authenticate())
          .addHandler(_router.call);

      // Access secure storage and check for certificates
      final storageService = SecureStorageService();
      var privateKeyPem = await storageService.getPrivateKey();
      var certificatePem = await storageService.getCertificate();

      // Generate self-signed certificates if missing
      if (privateKeyPem == null || certificatePem == null) {
        _logger.warning(
          'Certificates not found. Generating new self-signed certificates...',
        );
        await _dbService.insertLog(
          level: 'WARNING',
          message:
              'Certificates not found. '
              'Generating new self-signed certificates...',
        );
        final certData = await storageService.generateSelfSignedCertificate();
        privateKeyPem = certData['privateKey'];
        certificatePem = certData['certificate'];
        _logger.info('New certificates generated and stored securely.');
        await _dbService.insertLog(
          level: 'INFO',
          message: 'New certificates generated and stored securely.',
        );
      }

      // Create a SecurityContext for HTTPS
      final securityContext =
          SecurityContext()
            ..useCertificateChainBytes(certificatePem!.codeUnits)
            ..usePrivateKeyBytes(privateKeyPem!.codeUnits);

      _logger.info('Starting server on port $port...');
      await _dbService.insertLog(
        level: 'INFO',
        message: 'Starting server on port $port...',
      );

      // Bind the server to any IPv4 address
      _server = await serve(
        handler,
        InternetAddress.anyIPv4,
        port,
        securityContext: securityContext,
      );

      _logger.info(
        'Server started at https://${_server!.address.address}:${_server!.port}',
      );
      await _dbService.insertLog(
        level: 'INFO',
        message:
            'Server started at https://${_server!.address.address}:${_server!.port}',
      );
    } catch (e, st) {
      _logger.severe('Error starting the server', e, st);
      await _dbService.insertLog(
        level: 'ERROR',
        message: 'Error starting the server: $e',
        stackTrace: st.toString(),
      );
      throw Exception('Failed to start the server');
    }
  }

  /// Stops the running server
  Future<void> stop() async {
    if (!isRunning) {
      _logger.warning('Server is not running.');
      await _dbService.insertLog(
        level: 'WARNING',
        message: 'Server is not running.',
      );
      return;
    }

    try {
      await _server!.close(force: true);
      _server = null;
      _logger.info('Server stopped successfully.');
      await _dbService.insertLog(
        level: 'INFO',
        message: 'Server stopped successfully.',
      );
    } catch (e, st) {
      _logger.severe('Error stopping the server', e, st);
      await _dbService.insertLog(
        level: 'ERROR',
        message: 'Error stopping the server: $e',
        stackTrace: st.toString(),
      );
      throw Exception('Failed to stop the server');
    }
  }

  /// Initializes the router with all predefined routes
  void _initializeRoutes() {
    _router
      ..get('/', baseHandler)
      ..get('/favicon.ico', favicoHandler)
      ..post('/register', registerHandler)
      ..post('/login', loginHandler)
      ..get('/metadata', metadataHandler)
      ..all(r'/$validate', validateHandler)
      ..all(r'/<resourceType>/$validate', validateHandler)
      ..get('/<resourceType>', getResourcesHandler)
      ..post('/<resourceType>', postResourceHandler)
      ..get('/<resourceType>/<id>', getResourceByIdHandler)
      ..put('/<resourceType>/<id>', putResourceHandler);
  }

  /// Middleware for structured logging
  Middleware _logRequestsMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        final startTime = DateTime.now();
        final response = await innerHandler(request);
        final duration = DateTime.now().difference(startTime);

        // Extract user if available
        final user =
            request.context['authenticatedUser'] as String? ?? 'Anonymous';

        // Extract client IP
        // Extract client IP
        final clientIp =
            request.headers['x-forwarded-for'] ??
            (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)
                ?.remoteAddress
                .address ??
            'Unknown';

        // Log the request
        await _dbService.insertLog(
          level: 'INFO',
          message: 'Request received',
          method: request.method,
          url: request.requestedUri.toString(),
          statusCode: response.statusCode,
          responseTime: duration.inMilliseconds,
          clientIp: clientIp,
          user: user,
        );

        return response;
      };
    };
  }
}
