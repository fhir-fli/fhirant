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

    // Bind to any IPv4 address to allow external access
    _server = await serve(handler, InternetAddress.anyIPv4, port);

    // Retrieve and print the server's local IP address
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );

    String? localIpAddress;
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback) {
          localIpAddress = address.address;
          break;
        }
      }
    }

    if (localIpAddress != null) {
      print('Server started at http://$localIpAddress:${_server!.port}');
    } else {
      print(
        'Server started at http://${_server!.address.address}:${_server!.port}',
      );
    }
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
