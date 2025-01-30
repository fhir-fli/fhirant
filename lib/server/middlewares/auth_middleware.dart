import 'dart:convert';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:fhirant/fhirant.dart';
import 'package:shelf/shelf.dart';

const String _secretKey = 'your-very-secure-secret';

/// Middleware to authenticate requests
Middleware authenticate() {
  return (Handler innerHandler) {
    return (Request request) async {
      final path = request.url.path;

      // Allow public routes
      if (path == 'register' || path == 'login') {
        return innerHandler(request);
      }

      final authHeader = request.headers['Authorization'];
      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        LoggingService.logWarning('Unauthorized request to $path');
        return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
      }

      try {
        final token = authHeader.substring(7);
        final jwt = JWT.verify(token, SecretKey(_secretKey));

        LoggingService.logInfo(
          // ignore: avoid_dynamic_calls
          'Authenticated request to $path by ${jwt.payload['username']}',
        );

        final updatedRequest = request.change(context: {'user': jwt.payload});
        return innerHandler(updatedRequest);
      } catch (e) {
        LoggingService.logWarning('Invalid token used for $path');
        return Response.forbidden(jsonEncode({'error': 'Invalid token'}));
      }
    };
  };
}
