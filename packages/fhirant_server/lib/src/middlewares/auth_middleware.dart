import 'dart:convert';

import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:fhirant_server/src/utils/smart_scopes.dart';
import 'package:shelf/shelf.dart';

/// Paths that do not require authentication.
const _publicPrefixes = ['auth/', 'metadata', 'favicon.ico', '.well-known/'];

/// Middleware that validates JWT Bearer tokens, enforces SMART scopes,
/// and injects auth_user into the request context.
///
/// Public routes (auth/*, metadata, favicon.ico, .well-known/*, root)
/// pass through without authentication.
Middleware authMiddleware(JwtService jwtService) {
  return (Handler innerHandler) {
    return (Request request) async {
      final path = request.url.path;

      // Public routes: auth not required, but optionally inject auth_user
      // if a valid token is present (needed for e.g. admin registering users).
      final isPublic = path.isEmpty ||
          _publicPrefixes.any((prefix) => path.startsWith(prefix));
      if (isPublic) {
        final authHeader = request.headers['authorization'];
        if (authHeader != null && authHeader.startsWith('Bearer ')) {
          final payload = jwtService.verifyToken(authHeader.substring(7));
          if (payload != null) {
            final updatedRequest =
                request.change(context: {'auth_user': payload});
            return innerHandler(updatedRequest);
          }
        }
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

      // Extract scopes from JWT (fall back to role defaults for legacy tokens)
      final List<String> scopes;
      final scopeClaim = payload['scope'];
      if (scopeClaim is String && scopeClaim.isNotEmpty) {
        scopes = scopeClaim.split(' ');
      } else {
        final role = payload['role'] as String? ?? 'readonly';
        scopes = SmartScopeEnforcer.defaultScopesForRole(role);
      }

      // Extract patient context from JWT (for patient-level scopes)
      final patientId = payload['patient'] as String?;

      // Determine the required permission for this request
      final permission =
          SmartScopeEnforcer.methodToPermission(request.method, path);
      if (permission != null) {
        final resourceType =
            SmartScopeEnforcer.resourceTypeFromPath(path);
        // Only enforce scopes for resource-targeted requests
        if (resourceType != null) {
          if (!SmartScopeEnforcer.isAuthorized(
              scopes, resourceType, permission)) {
            return Response(403,
                body: jsonEncode({
                  'resourceType': 'OperationOutcome',
                  'issue': [
                    {
                      'severity': 'error',
                      'code': 'forbidden',
                      'diagnostics':
                          'Insufficient scope for $permission on $resourceType',
                    }
                  ]
                }));
          }

          // If patient/ scopes are present but no patient context, reject
          if (SmartScopeEnforcer.hasPatientScopes(scopes) &&
              patientId == null) {
            return Response(403,
                body: jsonEncode({
                  'resourceType': 'OperationOutcome',
                  'issue': [
                    {
                      'severity': 'error',
                      'code': 'forbidden',
                      'diagnostics':
                          'patient/ scopes require a patient context '
                          '(patient claim in JWT)',
                    }
                  ]
                }));
          }
        }
      }

      // Inject auth_user (with scopes and patient context) into context
      payload['scopes'] = scopes;
      if (patientId != null) {
        payload['patientId'] = patientId;
      }
      final updatedRequest =
          request.change(context: {'auth_user': payload});
      return innerHandler(updatedRequest);
    };
  };
}
