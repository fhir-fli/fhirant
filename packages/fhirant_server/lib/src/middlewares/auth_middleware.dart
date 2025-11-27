// import 'dart:convert';
// import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
// import 'package:fhirant_logging/fhirant_logging.dart';
// import 'package:shelf/shelf.dart';

// const String _secretKey = 'your-very-secure-secret';

// /// Middleware to authenticate requests
// Middleware authenticate() {
//   return (Handler innerHandler) {
//     return (Request request) async {
//       final path = request.url.path;

//       // Allow public routes
//       if (path == 'register' || path == 'login') {
//         return innerHandler(request);
//       }

//       final authHeader = request.headers['Authorization'];
//       if (authHeader == null || !authHeader.startsWith('Bearer ')) {
//         FhirantLogging().logWarning('Unauthorized request to $path');
//         return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
//       }

//       try {
//         final token = authHeader.substring(7);
//         final jwt = JWT.verify(token, SecretKey(_secretKey));

//         // Log the authenticated request, but avoid logging sensitive user data
//         FhirantLogging().logInfo(
//           'Authenticated request to $path by user '
//           '${(jwt.payload as Map<String, dynamic>)['username']}',
//         );

//         final updatedRequest = request.change(context: {'user': jwt.payload});
//         return innerHandler(updatedRequest);
//       } catch (e) {
//         FhirantLogging().logWarning('Invalid token used for $path');
//         return Response.forbidden(jsonEncode({'error': 'Invalid token'}));
//       }
//     };
//   };
// }
