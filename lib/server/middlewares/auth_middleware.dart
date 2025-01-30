
import 'dart:convert';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
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

      // Check Authorization header
      final authHeader = request.headers['Authorization'];
      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
      }

      try {
        final token = authHeader.substring(7);
        final jwt = JWT.verify(token, SecretKey(_secretKey));

        // Attach user info to request (optional)
        final updatedRequest = request.change(context: {'user': jwt.payload});

        return innerHandler(updatedRequest);
      } catch (e) {
        return Response.forbidden(jsonEncode({'error': 'Invalid token'}));
      }
    };
  };
}
