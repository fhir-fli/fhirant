// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:fhirant/fhirant.dart';
import 'package:fhirant/server/handlers/favico_handler.dart';
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

  /// Getter to check if the server is running
  bool get isRunning => _server != null;

  /// Getter to return the server port
  int? get port => _server?.port;

  /// Starts the server directly in the main isolate
  Future<void> start({int port = 8080}) async {
    if (isRunning) {
      print('Server is already running.');
      return;
    }

    try {
      _initializeRoutes();

      // Add middleware and assign the router as the handler
      final handler = const Pipeline()
          .addMiddleware(logRequests())
          .addHandler(_router.call);

      // Access secure storage and check for certificates
      final storageService = SecureStorageService();
      var privateKeyPem = await storageService.getPrivateKey();
      var certificatePem = await storageService.getCertificate();

      // Generate self-signed certificates if missing
      if (privateKeyPem == null || certificatePem == null) {
        print(
          'Certificates not found. Generating new self-signed certificates...',
        );
        final certData = await storageService.generateSelfSignedCertificate();
        privateKeyPem = certData['privateKey'];
        certificatePem = certData['certificate'];
        print('New certificates generated and stored securely.');
      }

      // Create a SecurityContext for HTTPS
      final securityContext =
          SecurityContext()
            ..useCertificateChainBytes(certificatePem!.codeUnits)
            ..usePrivateKeyBytes(privateKeyPem!.codeUnits);

      // Bind the server to any IPv4 address
      _server = await serve(
        handler,
        InternetAddress.anyIPv4,
        port,
        securityContext: securityContext,
      );

      // Print the server address
      print(
        'Server started at https://${_server!.address.address}:${_server!.port}',
      );
    } catch (e) {
      print('Error starting the server: $e');
      throw Exception('Failed to start the server');
    }
  }

  /// Stops the running server
  Future<void> stop() async {
    if (!isRunning) {
      print('Server is not running.');
      return;
    }

    try {
      await _server!.close(force: true);
      _server = null;
      print('Server stopped successfully.');
    } catch (e) {
      print('Error stopping the server: $e');
      throw Exception('Failed to stop the server');
    }
  }

  /// Initializes the router with all predefined routes
  void _initializeRoutes() {
    _router
      ..get('/', baseHandler) // Welcome route
      ..get('/favicon.ico', favicoHandler)
      ..post('/register', registerHandler) // Register route
      ..post('/login', loginHandler) // Login route
      ..get('/metadata', metadataHandler) // Capability statement
      ..all(r'/$validate', validateHandler) // Global validation
      ..all(
        r'/<resourceType>/$validate',
        validateHandler,
      ) // Resource validation
      ..get('/<resourceType>', getResourcesHandler) // Get all resources of type
      ..post('/<resourceType>', postResourceHandler) // Create resource
      ..get(
        '/<resourceType>/<id>',
        getResourceByIdHandler,
      ) // Get resource by ID
      ..put(
        '/<resourceType>/<id>',
        putResourceHandler,
      ); // Update resource by ID
  }
}
