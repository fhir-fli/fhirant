// import 'dart:async';
// import 'dart:io';

// import 'package:fhirant/fhirant.dart';
// import 'package:fhirant/server/handlers/favico_handler.dart';
// import 'package:fhirant_db/fhirant_db.dart';
// import 'package:fhirant_logging/fhirant_logging.dart';
// import 'package:fhirant_secure_storage/fhirant_secure_storage.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:shelf/shelf.dart';
// import 'package:shelf/shelf_io.dart';
// import 'package:shelf_rate_limiter/shelf_rate_limiter.dart';
// import 'package:shelf_router/shelf_router.dart' as shelf;

// /// Provider for the server manager
// final serverManagerProvider = Provider(
//   (ref) => ServerManager(ref.watch(dbServiceProvider)),
// );

// /// Provider for the test server manager
// final testServerManagerProvider = Provider(
//   (ref) => ServerManager(ref.watch(testDbServiceProvider)),
// );

// /// A singleton class to manage the server lifecycle and routing
// class ServerManager {
//   /// Default constructor
//   ServerManager(this._dbService);

//   HttpServer? _server; // Reference to the running server

//   /// Getter to check if the server is running
//   bool get isRunning => _server != null;

//   /// Getter to return the server port
//   int? get port => _server?.port;

//   /// Database service instance
//   final DbService _dbService;

//   /// Getter to check if registration is open
//   bool isRegistrationOpen = false;

//   /// Getter to return the registration code
//   String? _registrationCode;

//   /// Getter to return the registration code
//   String? get registrationCode => _registrationCode;

//   /// Start the server on the specified port
//   Future<void> start({int port = 8080}) async {
//     if (isRunning) {
//       FhirantLogging().logWarning('Server is already running.');
//       return;
//     }

//     // Fetch certificates before starting
//     final storageService = SecureStorageService();
//     final privateKeyPem = await storageService.getPrivateKey();
//     final certificatePem = await storageService.getCertificate();

//     if (privateKeyPem == null || certificatePem == null) {
//       FhirantLogging().logError(
//         'Missing certificates! Cannot start the server.',
//       );
//       return;
//     }

//     // Setup and start the server
//     await _runServer(port, privateKeyPem, certificatePem);
//   }

//   /// Stop the server
//   Future<void> stop() async {
//     if (!isRunning) {
//       FhirantLogging().logWarning('Server is not running.');
//       return;
//     }

//     FhirantLogging().logInfo('Stopping server...');
//     await _server!.close(force: true);
//     _server = null;
//     FhirantLogging().logInfo('Server stopped.');
//   }

//   /// Generate a new registration code
//   String generateRegistrationCode() {
//     _registrationCode = SecureStorageService.generateSecureRandomKey(32);
//     _resetRegistrationCodeInSeconds();
//     return _registrationCode!;
//   }

//   /// Check if the registration code is active
//   Future<void> _resetRegistrationCodeInSeconds([int seconds = 300]) async {
//     await Future<void>.delayed(Duration(seconds: seconds));
//     _registrationCode = null;
//   }

//   /// Cancel the registration code
//   Future<void> cancelRegistrationCode() async {
//     _registrationCode = null;
//   }

//   /// Allow general registration
//   void allowGeneralRegistration() {
//     isRegistrationOpen = true;
//     _resetGeneralRegistrationInSeconds();
//   }

//   /// Check if the registration code is active
//   Future<void> _resetGeneralRegistrationInSeconds([int seconds = 300]) async {
//     await Future<void>.delayed(Duration(seconds: seconds));
//     isRegistrationOpen = false;
//   }

//   /// Close general registration
//   void closeGeneralRegistration() {
//     isRegistrationOpen = false;
//   }

//   /// Runs the server in the main isolate
//   Future<void> _runServer(
//     int port,
//     String? privateKeyPem,
//     String? certificatePem,
//   ) async {
//     // Setup rate limiting
//     final memoryStorage = MemStorage(); // In-memory storage for rate limiting
//     final rateLimiter = ShelfRateLimiter(
//       storage: memoryStorage,
//       duration: const Duration(seconds: 60), // 60-second window
//       maxRequests: 10, // 10 requests per minute
//     );

//     final router = shelf.Router()
//       // ✅ Pass `_dbService` to each handler
//       ..get('/', baseHandler)
//       ..get('/favicon.ico', favicoHandler)
//       ..post(
//         '/register',
//         (Request req) =>
//             registerHandler(req, _registrationCode, isRegistrationOpen),
//       )
//       ..post('/login', loginHandler)
//       ..get('/metadata', metadataHandler)
//       ..all(r'/$validate', validateHandler)
//       ..all(r'/<resourceType>/$validate', validateHandler)
//       ..get(
//         '/<resourceType>',
//         (Request req, String resourceType) =>
//             getResourcesHandler(req, resourceType, _dbService),
//       )
//       ..post(
//         '/<resourceType>',
//         (Request req, String resourceType) =>
//             postResourceHandler(req, resourceType, _dbService),
//       )
//       ..get(
//         '/<resourceType>/<id>',
//         (Request req, String resourceType, String id) =>
//             getResourceByIdHandler(req, resourceType, id, _dbService),
//       )
//       ..put(
//         '/<resourceType>/<id>',
//         (Request req, String resourceType, String id) =>
//             putResourceHandler(req, resourceType, id, _dbService),
//       );

//     final handler = const Pipeline()
//         .addMiddleware(_logRequestsMiddleware())
//         // .addMiddleware(authenticate())
//         .addMiddleware(rateLimiter.rateLimiter()) // Add rate limiting here
//         .addHandler(router.call);

//     if (privateKeyPem == null || certificatePem == null) {
//       FhirantLogging().logWarning(
//         'Certificates not found. Cannot start server.',
//       );
//       return;
//     }

//     final securityContext = SecurityContext()
//       ..useCertificateChainBytes(certificatePem.codeUnits)
//       ..usePrivateKeyBytes(privateKeyPem.codeUnits);

//     _server = await serve(
//       handler,
//       InternetAddress.anyIPv4,
//       port,
//       securityContext: securityContext,
//     );

//     FhirantLogging().logInfo(
//       'Server started at https://${_server!.address.address}:${_server!.port}',
//     );
//   }

//   /// **Middleware for structured logging**
//   Middleware _logRequestsMiddleware() {
//     return (Handler innerHandler) {
//       return (Request request) async {
//         final startTime = DateTime.now();
//         final response = await innerHandler(request);
//         final duration = DateTime.now().difference(startTime);

//         final clientIp = request.headers['x-forwarded-for'] ??
//             (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)
//                 ?.remoteAddress
//                 .address ??
//             'Unknown';

//         await _dbService.insertLog(
//           level: 'INFO',
//           message: 'Request received',
//           method: request.method,
//           url: request.requestedUri.toString(),
//           statusCode: response.statusCode,
//           responseTime: duration.inMilliseconds,
//           clientIp: clientIp,
//           user: request.context['authenticatedUser'] as String? ?? 'Anonymous',
//         );

//         return response;
//       };
//     };
//   }
// }
