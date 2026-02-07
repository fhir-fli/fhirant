import 'dart:convert';

import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:shelf/shelf.dart';

/// Paths that do not require authentication.
const _publicPrefixes = ['auth/', 'metadata', 'favicon.ico'];

/// Middleware that validates JWT Bearer tokens and injects auth_user into
/// the request context.
///
/// Public routes (auth/*, metadata, favicon.ico, root) pass through.
/// Readonly users are blocked from mutating methods (POST, PUT, PATCH, DELETE).
Middleware authMiddleware(JwtService jwtService) {
  return (Handler innerHandler) {
    return (Request request) async {
      final path = request.url.path;

      // Allow public routes
      if (path.isEmpty ||
          _publicPrefixes.any((prefix) => path.startsWith(prefix))) {
        return innerHandler(request);
      }

      // Check for Authorization header
      final authHeader = request.headers['authorization'];
      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return Response(401,
            body: jsonEncode({
              'resourceType': 'OperationOutcome',
              'issue': [
                {
                  'severity': 'error',
                  'code': 'login',
                  'diagnostics': 'Missing or invalid Authorization header',
                }
              ]
            }));
      }

      // Verify token
      final token = authHeader.substring(7);
      final payload = jwtService.verifyToken(token);
      if (payload == null) {
        return Response(401,
            body: jsonEncode({
              'resourceType': 'OperationOutcome',
              'issue': [
                {
                  'severity': 'error',
                  'code': 'login',
                  'diagnostics': 'Token is invalid or expired',
                }
              ]
            }));
      }

      // Readonly enforcement
      if (payload['role'] == 'readonly' &&
          const ['POST', 'PUT', 'PATCH', 'DELETE']
              .contains(request.method)) {
        return Response(403,
            body: jsonEncode({
              'resourceType': 'OperationOutcome',
              'issue': [
                {
                  'severity': 'error',
                  'code': 'forbidden',
                  'diagnostics':
                      'Readonly users cannot perform ${request.method} operations',
                }
              ]
            }));
      }

      // Inject auth_user into context
      final updatedRequest =
          request.change(context: {'auth_user': payload});
      return innerHandler(updatedRequest);
    };
  };
}
