import 'dart:io';

import 'package:fhirant/router/handlers/base_handler.dart';
import 'package:fhirant/router/handlers/login_handler.dart';
import 'package:fhirant/router/handlers/metadata_handler.dart';
import 'package:fhirant/router/handlers/resource_handler.dart';
import 'package:fhirant/router/handlers/validate_handler.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';

/// Create the router itself
Future<HttpServer> createRouter({int port = 8080}) async {
  // Define router
  final router = Router()
        ..get('/', baseHandler) // Welcome route
        ..post('/login', loginHandler) // Login
        ..get('/metadata', metadataHandler) // Capability statement
        ..all(r'/$validate', validateHandler) // Global validation (GET or POST)
        ..all(
          r'/<resourceType>/$validate',
          validateHandler,
        ) // Resource-specific validation
        ..get(
          '/<resourceType>',
          getResourcesHandler,
        ) // Get all resources of type
        ..post('/<resourceType>', postResourceHandler) // Create resource
        ..get(
          '/<resourceType>/<id>',
          getResourceByIdHandler,
        ) // Get resource by ID
        ..put(
          '/<resourceType>/<id>',
          putResourceHandler,
        ) // Update resource by ID
      // ..delete('/<resourceType>/<id>', deleteResourceHandler) // Delete resource by ID
      // ..get('/admin/<endpoint>', adminHandler) // Admin route
      // ..get('/ws', websocketHandler) // WebSocket
      ;
  // Add middleware
  final handler = const Pipeline()
      .addMiddleware(logRequests()) // Logs requests
      // .addMiddleware(authMiddleware()) // Auth middleware
      .addHandler(router.call);

  // Bind to an available port and listen for requests
  final server = await serve(handler, InternetAddress.loopbackIPv4, port);
  print('Server running on http://${server.address.address}:${server.port}');
  return server;
}
