import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/auth/request_authorization.dart';
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

/// Whether [request] is one of the routes that take no credential.
///
/// The root is public for the welcome page only: a bare `GET /`. `POST /`
/// is the transaction/batch endpoint and `GET /?…` the system search, and
/// both used to pass here because the path is empty, so a transaction
/// Bundle and a search of every resource type needed no token at all
/// (REVIEW-2026-09-08 row 1).
bool _isPublic(Request request) {
  final path = request.url.path;
  if (path.isEmpty) {
    return request.method == 'GET' && !request.url.hasQuery;
  }
  return _publicPaths.contains(path) || _publicPrefixes.any(path.startsWith);
}

/// Middleware that validates JWT Bearer tokens, enforces SMART scopes,
/// and injects auth_user into the request context.
///
/// Public routes (auth/*, metadata, favicon.ico, .well-known/*, a bare
/// `GET /`) pass through without authentication.
Middleware authMiddleware(JwtService jwtService, FhirAntDb dbInterface) {
  return (Handler innerHandler) {
    return (Request request) async {
      final path = request.url.path;

      // Public routes: auth not required, but optionally inject auth_user
      // if a valid token is present (needed for e.g. admin registering users).
      if (_isPublic(request)) {
        final authHeader = request.headers['authorization'];
        if (authHeader != null && authHeader.startsWith('Bearer ')) {
          final rawToken = authHeader.substring(7);
          final payload = jwtService.verifyAccessToken(rawToken);
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
        return unauthorized('Missing or invalid Authorization header');
      }

      // Verify token. A refresh token is a valid signature with the wrong
      // job: it lives seven days to the access token's eight hours and is
      // meant only for `/auth/token`. It used to authenticate any request
      // (REVIEW-2026-09-06 finding 2).
      final token = authHeader.substring(7);
      final payload = jwtService.verifyAccessToken(token);
      if (payload == null) {
        return unauthorized('Token is invalid or expired');
      }

      // Check if the token has been revoked
      final revoked = await dbInterface.isTokenRevoked(TokenHasher.hash(token));
      if (revoked) {
        return unauthorized('Token has been revoked');
      }

      // The account behind the token, re-read on every request: one indexed
      // read by id. A token used to authenticate for its whole life (8 h;
      // the refresh token 7 d) after the account was deactivated or locked,
      // because nothing here looked at the account again
      // (REVIEW-2026-09-08 row 14). An account cannot be deleted, only
      // deactivated, so a missing row is a token this store never issued.
      final rawUserId = payload['userId'];
      final userId =
          rawUserId is int ? rawUserId : int.tryParse('$rawUserId') ?? -1;
      final account = await dbInterface.getUserById(userId);
      if (account == null) {
        return unauthorized('The account this token names does not exist');
      }
      if (!account.active) {
        return unauthorized('Account is deactivated');
      }
      final lockedUntil = account.lockedUntil;
      if (lockedUntil != null && lockedUntil.isAfter(DateTime.now())) {
        return unauthorized('Account is locked');
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
        return forbidden(
          'Token carries a scope this server does not understand. Scopes '
          'must use SMART v2 syntax (context/Resource.cruds).',
        );
      }

      final principal = Principal(
        userId: userId,
        username: payload['username'] as String? ?? account.username,
        role: payload['role'] as String? ?? account.role,
        scopes: scopes,
        patientId: payload['patient'] as String?,
      );
      final refused = authorizeRequest(principal, request.method, path);
      if (refused != null) return refused;

      // Inject auth_user (with scopes and patient context) into context
      payload['scopes'] = scopes;
      if (principal.patientId != null) {
        payload['patientId'] = principal.patientId;
      }
      final updatedRequest = request.change(context: {'auth_user': payload});
      return innerHandler(updatedRequest);
    };
  };
}
