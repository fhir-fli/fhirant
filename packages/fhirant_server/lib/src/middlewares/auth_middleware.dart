import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:fhirant_server/src/utils/smart_scopes.dart';
import 'package:fhirant_server/src/utils/token_hasher.dart';
import 'package:shelf/shelf.dart';

/// Path prefixes that do not require authentication.
///
/// Genuine prefixes only — each names a subtree. Single paths go in
/// [_publicPaths] and are matched exactly, so that a future route merely
/// beginning with one of these words does not become unauthenticated by
/// accident.
const _publicPrefixes = [
  'auth/',
  '.well-known/',
];

/// Exact paths that do not require authentication.
const _publicPaths = {
  'metadata',
  'favicon.ico',
  'health',
};

/// Middleware that validates JWT Bearer tokens, enforces SMART scopes,
/// and injects auth_user into the request context.
///
/// Public routes (auth/*, metadata, favicon.ico, .well-known/*, root)
/// pass through without authentication.
Middleware authMiddleware(JwtService jwtService, FhirAntDb dbInterface) {
  return (Handler innerHandler) {
    return (Request request) async {
      final path = request.url.path;

      // Public routes: auth not required, but optionally inject auth_user
      // if a valid token is present (needed for e.g. admin registering users).
      final isPublic = path.isEmpty ||
          _publicPaths.contains(path) ||
          _publicPrefixes.any(path.startsWith);
      if (isPublic) {
        final authHeader = request.headers['authorization'];
        if (authHeader != null && authHeader.startsWith('Bearer ')) {
          final rawToken = authHeader.substring(7);
          final payload = jwtService.verifyToken(rawToken);
          if (payload != null) {
            // Check revocation — skip injecting auth_user if revoked
            final revoked =
                await dbInterface.isTokenRevoked(TokenHasher.hash(rawToken));
            if (!revoked) {
              final updatedRequest =
                  request.change(context: {'auth_user': payload});
              return innerHandler(updatedRequest);
            }
          }
        }
        return innerHandler(request);
      }

      // Check for Authorization header
      final authHeader = request.headers['authorization'];
      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return Response(
          401,
          body: jsonEncode({
            'resourceType': 'OperationOutcome',
            'issue': [
              {
                'severity': 'error',
                'code': 'login',
                'diagnostics': 'Missing or invalid Authorization header',
              }
            ],
          }),
        );
      }

      // Verify token
      final token = authHeader.substring(7);
      final payload = jwtService.verifyToken(token);
      if (payload == null) {
        return Response(
          401,
          body: jsonEncode({
            'resourceType': 'OperationOutcome',
            'issue': [
              {
                'severity': 'error',
                'code': 'login',
                'diagnostics': 'Token is invalid or expired',
              }
            ],
          }),
        );
      }

      // Check if the token has been revoked
      final revoked = await dbInterface.isTokenRevoked(TokenHasher.hash(token));
      if (revoked) {
        return Response(
          401,
          body: jsonEncode({
            'resourceType': 'OperationOutcome',
            'issue': [
              {
                'severity': 'error',
                'code': 'login',
                'diagnostics': 'Token has been revoked',
              }
            ],
          }),
        );
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

      // A scope this server cannot parse is refused, not skipped. Skipping it
      // is not the safe direction: the unparsed entry may be the one that
      // NARROWS access, in which case dropping it leaves the broader scopes
      // standing and the token ends up more powerful than its issuer intended.
      if (!SmartScopeEnforcer.allScopesParse(scopes)) {
        return Response(
          403,
          body: jsonEncode({
            'resourceType': 'OperationOutcome',
            'issue': [
              {
                'severity': 'error',
                'code': 'forbidden',
                'diagnostics': 'Token carries a scope this server does not '
                    'understand. Scopes must use SMART v2 syntax '
                    '(context/Resource.cruds).',
              }
            ],
          }),
        );
      }

      // Extract patient context from JWT (for patient-level scopes)
      final patientId = payload['patient'] as String?;

      // Privileged root-level system operations ($backup/$restore/$export…)
      // carry no resource type, so the resource-scope check below never
      // covers them. Enforce system-level authorization (admin role, or an
      // explicit system/ scope) here, or any authenticated user — including
      // readonly — could dump or overwrite the entire database.
      //
      // On a single-operator on-device deployment the sole account is the
      // bootstrap admin, so this does not impede the intended mobile use.
      if (SmartScopeEnforcer.isPrivilegedSystemOperation(path)) {
        final role = payload['role'] as String? ?? 'readonly';
        if (!SmartScopeEnforcer.isSystemAuthorized(scopes, role)) {
          return Response(
            403,
            body: jsonEncode({
              'resourceType': 'OperationOutcome',
              'issue': [
                {
                  'severity': 'error',
                  'code': 'forbidden',
                  'diagnostics': 'This operation requires system-level (admin) '
                      'privilege.',
                }
              ],
            }),
          );
        }
      }

      // Determine the required permission for this request
      final permission =
          SmartScopeEnforcer.methodToPermission(request.method, path);

      // Root-level operations name no resource type, so the resource-scope
      // check below cannot cover them and used to let any authenticated
      // caller through — including a read-only or patient-scoped one. Since
      // several of them read arbitrary stored data ($fhirpath fetches any
      // resource by id), they are gated here instead, deny-by-default: only
      // the operations that work purely on what the caller posted are exempt.
      if (SmartScopeEnforcer.isRootDataOperation(path)) {
        if (!SmartScopeEnforcer.isUnscopedDataAccessAuthorized(
          scopes,
          permission ?? 'r',
        )) {
          return Response(
            403,
            body: jsonEncode({
              'resourceType': 'OperationOutcome',
              'issue': [
                {
                  'severity': 'error',
                  'code': 'forbidden',
                  'diagnostics': 'This operation can return data the request '
                      'does not name, so it requires a user- or system-context '
                      'scope covering all resource types.',
                }
              ],
            }),
          );
        }
      }
      if (permission != null) {
        final resourceType = SmartScopeEnforcer.resourceTypeFromPath(path);
        // Only enforce scopes for resource-targeted requests
        if (resourceType != null) {
          if (!SmartScopeEnforcer.isAuthorized(
            scopes,
            resourceType,
            permission,
          )) {
            return Response(
              403,
              body: jsonEncode({
                'resourceType': 'OperationOutcome',
                'issue': [
                  {
                    'severity': 'error',
                    'code': 'forbidden',
                    'diagnostics':
                        'Insufficient scope for $permission on $resourceType',
                  }
                ],
              }),
            );
          }

          // If patient/ scopes are present but no patient context, reject
          if (SmartScopeEnforcer.hasPatientScopes(scopes) &&
              patientId == null) {
            return Response(
              403,
              body: jsonEncode({
                'resourceType': 'OperationOutcome',
                'issue': [
                  {
                    'severity': 'error',
                    'code': 'forbidden',
                    'diagnostics': 'patient/ scopes require a patient context '
                        '(patient claim in JWT)',
                  }
                ],
              }),
            );
          }
        }
      }

      // Inject auth_user (with scopes and patient context) into context
      payload['scopes'] = scopes;
      if (patientId != null) {
        payload['patientId'] = patientId;
      }
      final updatedRequest = request.change(context: {'auth_user': payload});
      return innerHandler(updatedRequest);
    };
  };
}
