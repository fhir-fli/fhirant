// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:fhirant/fhirant.dart';
import 'package:fhirant/server/handlers/favico_handler.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';

/// A singleton class to manage the server lifecycle and routing
class ServerManager {
  /// Factory constructor to return the singleton instance
  factory ServerManager() => _instance;

  /// Private constructor to enforce singleton pattern
  ServerManager._();

  /// Singleton instance
  static final ServerManager _instance = ServerManager._();

  HttpServer? _server; // Reference to the running server
  final Router _router = Router(); // Router instance for defining routes

  /// Checks if the server is running
  bool get isRunning => _server != null;

  /// Returns the address of the running server
  String? get address => _server?.address.address;

  /// Returns the port of the running server
  int? get port => _server?.port;

  /// Initializes the router with all the predefined routes
  void _initializeRoutes() {
    _router
      ..get('/', baseHandler) // Welcome route
      ..get('/favicon.ico', favicoHandler)
      ..post('/login', loginHandler) // Login route
      ..get('/metadata', metadataHandler) // Capability statement
      ..all(r'/$validate', validateHandler) // Global validation (GET or POST)
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

  /// Starts the server on the specified port
  /// Throws an exception if the server is already running
  Future<void> start({int port = 8080}) async {
    if (isRunning) {
      throw Exception('Server is already running on http://$address:$port');
    }

    // Initialize routes
    _initializeRoutes();

    // Add middleware and assign handler
    final handler =
        const Pipeline().addMiddleware(logRequests()).addHandler(_router.call);

    // Log all network interfaces and their IPs
    final interfaces =
        await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        print('Found interface: ${interface.name}, IP: ${address.address}');
      }
    }

    // Access secure storage and check for certificates
    final storageService = SecureStorageService();
    var privateKeyPem = await storageService.getPrivateKey();
    var certificatePem = await storageService.getCertificate();

    // If certificates are missing, generate and save them
    if (privateKeyPem == null || certificatePem == null) {
      print(
        'Certificates not found. Generating new self-signed certificates...',
      );
      final certData = await storageService.generateSelfSignedCertificate();
      privateKeyPem = certData['privateKey'];
      certificatePem = certData['certificate'];
      print('New certificates generated and stored securely.');
    }

    if (certificatePem == null) {
      throw Exception('Certificate not found');
    }

    if (privateKeyPem == null) {
      throw Exception('Private key not found');
    }

    // Create a SecurityContext for HTTPS
    final securityContext = SecurityContext()
      ..useCertificateChainBytes(certificatePem.codeUnits)
      ..usePrivateKeyBytes(privateKeyPem.codeUnits);

    // Bind to any IPv4 address to allow external access
    _server = await serve(
      handler,
      InternetAddress.anyIPv4,
      port,
      securityContext: securityContext,
    );

    print(
      'Server started at https://${_server!.address.address}:${_server!.port}',
    );
  }

  /// Stops the server if it is running
  /// Throws an exception if the server is not running
  Future<void> stop() async {
    if (!isRunning) {
      throw Exception('Server is not running');
    }

    await _server!.close(force: true);
    _server = null;
    print('Server stopped');
  }
}
