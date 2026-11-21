import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/auth/request_authorization.dart';
import 'package:fhirant_server/src/auth/token_bound.dart';
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

/// Response-context key naming who the auth check established, read by the
/// audit middleware, which runs OUTSIDE this one so that it sees refusals
/// too (a refused token, a deactivated account and a missing scope used to
/// leave no audit record; measured 2026-09-21, 0 records each).
///
/// `userId` is present only when the server's own signature on the token
/// was verified; a garbled token proves nothing and names no one.
const auditAgentKey = 'audit_agent';

/// [response] carrying [agent] for the audit trail.
Response _withAgent(Response response, Map<String, dynamic> agent) =>
    response.change(context: {auditAgentKey: agent});

/// The account a verified token names by its `sub` ([User.accountKey]),
/// or null. The token's `sub` is the only thing read from it about the
/// account: ids restart at 1 in every store, and a token naming an id named
/// whoever held that number in another store sharing the signing secret
/// (REVIEW-2026-10-17, ASVS 5.0.0 V10.3.3; JwtService).
Future<User?> _accountOf(Map<String, dynamic> payload, FhirAntDb db) {
  final sub = payload['sub'];
  return sub is String ? db.getUserByAccountKey(sub) : Future.value();
}

/// The scopes a token carries, or null when it carries none.
List<String>? _tokenScopes(Map<String, dynamic> payload) {
  final claim = payload['scope'];
  return claim is String && claim.isNotEmpty ? claim.split(' ') : null;
}

/// What the rest of the server reads as `auth_user`: the token's own claims,
/// with who the caller is and what it holds taken from [account]. The
/// role and the patient context are the account's, and the scopes are the
/// token's narrowed to what the account holds now
/// ([SmartScopeEnforcer.grantScopes]). The role was the token's: a token
/// minted as an administrator stayed one on a store whose account of that
/// id was a clinician (probe of 2026-11-21).
Map<String, dynamic> _authUser(
  Map<String, dynamic> payload,
  User account,
  List<String> scopes,
) =>
    {
      ...payload,
      'userId': account.id,
      'username': account.username,
      'role': account.role,
      'scope': scopes.join(' '),
      'scopes': scopes,
      if (account.patientId != null) 'patientId': account.patientId,
    };

/// [requested] narrowed to what [account] holds now; with no scope claim,
/// what it holds. A `patient/` scope is kept when the account has no
/// patient, so that [authorizeRequest] refuses it (REVIEW-2026-09-17 A1)
/// rather than the request going on with no scope at all, which the root
/// `_history` and `_search` answer as an empty page.
List<String> _scopesNow(List<String>? requested, User account) =>
    SmartScopeEnforcer.grantScopes(
      requested ?? const [],
      SmartScopeEnforcer.heldScopes(account),
    );

/// Middleware that validates JWT Bearer tokens, enforces SMART scopes,
/// and injects auth_user into the request context. Every response it
/// returns or passes on carries, under [auditAgentKey], whoever the token
/// proved to be, refused or not.
///
/// Public routes (auth/*, metadata, favicon.ico, .well-known/*, a bare
/// `GET /`) pass through without authentication.
Middleware authMiddleware(JwtService jwtService, FhirAntDb dbInterface) {
  return (Handler innerHandler) {
    return (Request request) async {
      final path = request.url.path;

      // Public routes: auth not required, but optionally inject auth_user
      // if a valid token is present (needed for e.g. admin registering users).
      //
      // The token is held to the same four checks as on a protected route:
      // not revoked, its account exists, is active, and the token is of the
      // account's current generation. One that fails any of them is treated
      // as absent, and the request goes on anonymous, as a revoked one
      // always did. Only the first check ran here, so a deactivated or
      // demoted administrator's token, refused everywhere else, was injected
      // as an administrator and `POST /auth/register` trusted it: it created
      // a new administrator (REVIEW-2026-10-06 finding 1, probe P1).
      if (_isPublic(request)) {
        final authHeader = request.headers['authorization'];
        if (authHeader != null && authHeader.startsWith('Bearer ')) {
          final rawToken = authHeader.substring(7);
          final payload = jwtService.verifyAccessToken(rawToken);
          final requested = payload == null ? null : _tokenScopes(payload);
          if (payload != null &&
              SmartScopeEnforcer.allScopesParse(requested ?? const [])) {
            final revoked =
                await dbInterface.isTokenRevoked(TokenHasher.hash(rawToken));
            final account =
                revoked ? null : await _accountOf(payload, dbInterface);
            if (account != null &&
                account.active &&
                !tokenPredatesAccount(payload, account)) {
              final authUser = _authUser(
                payload,
                account,
                _scopesNow(requested, account),
              );
              final updatedRequest =
                  request.change(context: {'auth_user': authUser});
              return _withAgent(await innerHandler(updatedRequest), authUser);
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
      // From here the server's signature is verified; the token proves
      // which account key it was issued to, and nothing yet about who that
      // is here.
      // The account behind the token, re-read on every request: one indexed
      // read by key. A token used to authenticate for its whole life (8 h;
      // the refresh token 7 d) after the account was deactivated or locked,
      // because nothing here looked at the account again
      // (REVIEW-2026-09-08 row 14). An account cannot be deleted, only
      // deactivated, so a missing row is a token this store never issued:
      // its `sub` names no one here, and the audit record names no one.
      final account = await _accountOf(payload, dbInterface);
      if (account == null) {
        return unauthorized('The account this token names does not exist');
      }
      final known = <String, dynamic>{
        'userId': account.id,
        'username': account.username,
      };

      // Check if the token has been revoked
      final revoked = await dbInterface.isTokenRevoked(TokenHasher.hash(token));
      if (revoked) {
        return _withAgent(unauthorized('Token has been revoked'), known);
      }
      if (!account.active) {
        return _withAgent(unauthorized('Account is deactivated'), known);
      }
      // A token from before the account's password, role, scopes or
      // activation last changed is over (token_bound.dart; REVIEW-2026-09-17
      // A14).
      if (tokenPredatesAccount(payload, account)) {
        return _withAgent(
          unauthorized('Token predates a change to the account'),
          known,
        );
      }
      // A lock (five wrong passwords) blocks password login; it does not
      // end sessions. It did: five anonymous wrong passwords against a
      // known username, repeatable every fifteen minutes, kept that
      // account's valid token out (REVIEW-2026-09-17 A3). Revoking a
      // session is `/auth/revoke` or deactivating the account.

      final requested = _tokenScopes(payload);

      // A scope this server cannot parse is refused, not skipped. Skipping it
      // is not the safe direction: the unparsed entry may be the one that
      // NARROWS access, in which case dropping it leaves the broader scopes
      // standing and the token ends up more powerful than its issuer intended.
      if (!SmartScopeEnforcer.allScopesParse(requested ?? const [])) {
        return _withAgent(
          forbidden(
            'Token carries a scope this server does not understand. Scopes '
            'must use SMART v2 syntax (context/Resource.cruds).',
          ),
          known,
        );
      }

      final scopes = _scopesNow(requested, account);
      final principal = Principal(
        userId: account.id,
        username: account.username,
        role: account.role,
        scopes: scopes,
        patientId: account.patientId,
      );
      final refused = authorizeRequest(principal, request.method, path);
      if (refused != null) return _withAgent(refused, known);

      final authUser = _authUser(payload, account, scopes);
      final updatedRequest = request.change(context: {'auth_user': authUser});
      return _withAgent(await innerHandler(updatedRequest), authUser);
    };
  };
}
