import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/auth/token_bound.dart';
import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:fhirant_server/src/utils/no_store.dart';
import 'package:fhirant_server/src/utils/pkce.dart';
import 'package:fhirant_server/src/utils/smart_scopes.dart';
import 'package:fhirant_server/src/utils/token_hasher.dart';
import 'package:shelf/shelf.dart';

/// Handler for token exchange and refresh.
///
/// POST /auth/token
///
/// Supports two grant types:
/// - `grant_type=refresh_token` — exchange a refresh token for new tokens
/// - `grant_type=authorization_code` — exchange an authorization code
///   for tokens
Future<Response> refreshHandler(
  Request request,
  FhirAntDb dbInterface,
  JwtService jwtService,
) async {
  try {
    // Support both JSON and form-encoded bodies
    final bodyStr = await request.readAsString();
    Map<String, dynamic> body;
    try {
      body = jsonDecode(bodyStr) as Map<String, dynamic>;
    } catch (_) {
      // Fall back to form-encoded (standard OAuth 2.0 uses form-encoded)
      body = Map<String, dynamic>.from(Uri.splitQueryString(bodyStr));
    }

    final grantType = body['grant_type'] as String?;

    if (grantType == 'authorization_code') {
      return await _handleAuthorizationCodeGrant(body, dbInterface, jwtService);
    }

    if (grantType == 'refresh_token') {
      return await _handleRefreshTokenGrant(body, jwtService, dbInterface);
    }

    return Response(
      400,
      body: jsonEncode({
        'error': 'unsupported_grant_type',
        'error_description':
            'Supported grant types: authorization_code, refresh_token',
      }),
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('Token exchange failed', e, stackTrace);
    return Response.internalServerError(
      body: jsonEncode({
        'error': 'server_error',
        'error_description': 'Token exchange failed',
      }),
    );
  }
}

/// Exchange an authorization code for access + refresh tokens.
Future<Response> _handleAuthorizationCodeGrant(
  Map<String, dynamic> body,
  FhirAntDb dbInterface,
  JwtService jwtService,
) async {
  final code = body['code'] as String?;
  final redirectUri = body['redirect_uri'] as String?;
  final clientId = body['client_id'] as String?;
  final codeVerifier = body['code_verifier'] as String?;

  if (code == null || code.isEmpty) {
    return Response(
      400,
      body: jsonEncode({
        'error': 'invalid_request',
        'error_description': 'code is required',
      }),
    );
  }

  if (redirectUri == null || redirectUri.isEmpty) {
    return Response(
      400,
      body: jsonEncode({
        'error': 'invalid_request',
        'error_description': 'redirect_uri is required',
      }),
    );
  }

  // Look up the authorization code
  final authCode = await dbInterface.getAuthorizationCode(code);
  if (authCode == null) {
    return Response(
      400,
      body: jsonEncode({
        'error': 'invalid_grant',
        'error_description': 'Authorization code not found',
      }),
    );
  }

  // RFC 6749 §4.1.2 (read 2026-09-19, verbatim): "If an authorization code
  // is used more than once, the authorization server MUST deny the request
  // and SHOULD revoke (when possible) all tokens previously issued based on
  // that authorization code." The tokens issued on the first exchange
  // carry the account's token generation; moving it on ends them
  // (auth/token_bound.dart). REVIEW-2026-09-17 A16.
  if (authCode.used) {
    return _codeReused(dbInterface, authCode);
  }

  // Check expiration
  if (DateTime.now().isAfter(authCode.expiresAt)) {
    await dbInterface.markAuthorizationCodeUsed(code);
    return Response(
      400,
      body: jsonEncode({
        'error': 'invalid_grant',
        'error_description': 'Authorization code has expired',
      }),
    );
  }

  // Validate redirect_uri matches
  if (authCode.redirectUri != redirectUri) {
    return Response(
      400,
      body: jsonEncode({
        'error': 'invalid_grant',
        'error_description': 'redirect_uri does not match',
      }),
    );
  }

  // Validate client_id matches (if provided)
  if (clientId != null && authCode.clientId != clientId) {
    return Response(
      400,
      body: jsonEncode({
        'error': 'invalid_grant',
        'error_description': 'client_id does not match',
      }),
    );
  }

  // Verify PKCE if code_challenge was stored
  if (authCode.codeChallenge != null && authCode.codeChallengeMethod != null) {
    if (codeVerifier == null || codeVerifier.isEmpty) {
      return Response(
        400,
        body: jsonEncode({
          'error': 'invalid_request',
          'error_description':
              'code_verifier is required (PKCE was used during authorization)',
        }),
      );
    }
    if (!Pkce.verifyCodeChallenge(
      codeVerifier: codeVerifier,
      codeChallenge: authCode.codeChallenge!,
      codeChallengeMethod: authCode.codeChallengeMethod!,
    )) {
      return Response(
        400,
        body: jsonEncode({
          'error': 'invalid_grant',
          'error_description': 'PKCE code_verifier does not match',
        }),
      );
    }
  }

  // Consume the code in one statement. The check above and this mark used
  // to be two statements, so two exchanges of the same code arriving
  // together both passed the check and both got tokens (A16). The one that
  // loses the race is the reuse.
  if (!await dbInterface.consumeAuthorizationCode(code)) {
    return _codeReused(dbInterface, authCode);
  }

  // Look up the user
  final user = await dbInterface.getUserById(authCode.userId);
  if (user == null) {
    return Response(
      400,
      body: jsonEncode({
        'error': 'invalid_grant',
        'error_description': 'User no longer exists',
      }),
    );
  }

  if (!user.active) {
    return Response(
      403,
      body: jsonEncode({
        'error': 'invalid_grant',
        'error_description': 'Account is deactivated',
      }),
    );
  }

  // The scope stored with the code is already the requested scope
  // intersected with the account's grant (authorize_handler). The token's
  // scope claim carries the resource scopes; launch and OpenID scopes are
  // echoed in the response only.
  final held = SmartScopeEnforcer.heldScopes(user);
  final granted = authCode.scope.isNotEmpty
      ? authCode.scope.split(' ')
      : List<String>.of(held);
  final scopes = SmartScopeEnforcer.resourceScopesOf(granted);
  // The patient context is the account's, never the caller's.
  final patientId = user.patientId;
  final session = jwtService.issueSession(user, scopes: scopes);
  final accessToken = session.access;
  final refreshToken = session.refresh;

  return Response.ok(
    jsonEncode({
      'access_token': accessToken,
      'token_type': 'Bearer',
      'refresh_token': refreshToken,
      'scope': granted.join(' '),
      'username': user.username,
      'role': user.role,
      if (patientId != null) 'patient': patientId,
    }),
    headers: jsonNoStoreHeaders,
  );
}

/// A second use of an authorization code: denied, and every token the
/// account holds is ended, since the ones issued on the first use cannot
/// be told apart from the rest (RFC 6749 §4.1.2, above).
Future<Response> _codeReused(
  FhirAntDb dbInterface,
  AuthorizationCode authCode,
) async {
  await dbInterface.bumpTokenGeneration(authCode.userId);
  FhirantLogging().logWarning(
    'Authorization code reused for user ${authCode.userId}; '
    'its sessions are ended',
  );
  return Response(
    400,
    body: jsonEncode({
      'error': 'invalid_grant',
      'error_description': 'Authorization code has already been used',
    }),
  );
}

/// Exchange a refresh token for new access + refresh tokens.
Future<Response> _handleRefreshTokenGrant(
  Map<String, dynamic> body,
  JwtService jwtService,
  FhirAntDb dbInterface,
) async {
  final refreshToken = body['refresh_token'] as String?;
  if (refreshToken == null || refreshToken.isEmpty) {
    return Response(
      400,
      body: jsonEncode({
        'error': 'invalid_request',
        'error_description': 'refresh_token is required',
      }),
    );
  }

  // Verify the refresh token
  final payload = jwtService.verifyRefreshToken(refreshToken);
  if (payload == null) {
    return Response(
      401,
      body: jsonEncode({
        'error': 'invalid_grant',
        'error_description': 'Refresh token is invalid or expired',
      }),
    );
  }

  // Verify the user still exists and is active
  final userId = payload['userId'] as int?;
  final username = payload['username'] as String?;
  if (userId == null || username == null) {
    return Response(
      401,
      body: jsonEncode({
        'error': 'invalid_grant',
        'error_description': 'Invalid refresh token payload',
      }),
    );
  }

  final user = await dbInterface.getUserByUsername(username);
  if (user == null || user.id != userId) {
    return Response(
      401,
      body: jsonEncode({
        'error': 'invalid_grant',
        'error_description': 'User no longer exists',
      }),
    );
  }

  if (!user.active) {
    return Response(
      403,
      body: jsonEncode({
        'error': 'invalid_grant',
        'error_description': 'Account is deactivated',
      }),
    );
  }

  // A refresh token that was rotated away (or revoked) and is presented
  // again. RFC 9700 §4.14.2, refresh token rotation (read 2026-09-19,
  // verbatim): "If a refresh token is compromised and subsequently used by
  // both the attacker and the legitimate client, one of them will present
  // an invalidated refresh token, which will inform the authorization
  // server of the breach. The authorization server cannot determine which
  // party submitted the invalid refresh token, but it will revoke the
  // active refresh token. This stops the attack at the cost of forcing
  // the legitimate client to obtain a fresh authorization grant." Moving
  // the account's token generation on ends the active refresh token and
  // every access token with it (auth/token_bound.dart). Checked after the
  // signature and the account, so only a token this server issued for a
  // live account can end its sessions (REVIEW-2026-09-17 A16: reuse used
  // to be answered 401 and nothing else).
  final refreshHash = TokenHasher.hash(refreshToken);
  if (await dbInterface.isTokenRevoked(refreshHash)) {
    await dbInterface.bumpTokenGeneration(user.id);
    FhirantLogging().logWarning(
      'Revoked refresh token presented for user ${user.id}; '
      'its sessions are ended',
    );
    return Response(
      401,
      body: jsonEncode({
        'error': 'invalid_grant',
        'error_description': 'Refresh token has been revoked',
      }),
    );
  }
  // A refresh token from before the account's password, role, scopes or
  // activation last changed is over too (token_bound.dart;
  // REVIEW-2026-09-17 A14).
  if (tokenPredatesAccount(payload, user)) {
    return Response(
      401,
      body: jsonEncode({
        'error': 'invalid_grant',
        'error_description': 'Refresh token predates a change to the account',
      }),
    );
  }

  // The refresh token's scopes, narrowed to what the account holds NOW, so
  // an administrator's downgrade takes effect at the next refresh rather
  // than at the refresh token's expiry. The patient context is re-read
  // from the account for the same reason.
  final held = SmartScopeEnforcer.heldScopes(user);
  final scopeStr = payload['scope'] as String?;
  final carried =
      scopeStr != null && scopeStr.isNotEmpty ? scopeStr.split(' ') : held;
  final scopes = SmartScopeEnforcer.resourceScopesOf(
    SmartScopeEnforcer.grantScopes(
      carried,
      held,
      patientContext: user.patientId != null,
    ),
  );
  final patientId = user.patientId;
  final session = jwtService.issueSession(user, scopes: scopes);
  final newAccessToken = session.access;
  final newRefreshToken = session.refresh;

  // Revoke the old refresh token (rotation revocation)
  final oldExpiresAt = _extractExpiresAt(refreshToken);
  await dbInterface.revokeToken(refreshHash, oldExpiresAt);

  return Response.ok(
    jsonEncode({
      'access_token': newAccessToken,
      'token_type': 'Bearer',
      'refresh_token': newRefreshToken,
      'scope': scopes.join(' '),
      'username': user.username,
      'role': user.role,
      'scopes': scopes,
      if (patientId != null) 'patient': patientId,
    }),
    headers: jsonNoStoreHeaders,
  );
}

/// Extract expiration from a JWT without signature verification.
/// Falls back to now + 24 hours if the token can't be decoded.
DateTime _extractExpiresAt(String token) {
  try {
    final jwt = JWT.decode(token);
    final payload = jwt.payload as Map<String, dynamic>?;
    if (payload != null && payload.containsKey('exp')) {
      return DateTime.fromMillisecondsSinceEpoch(
        (payload['exp'] as num).toInt() * 1000,
      );
    }
  } catch (_) {
    // Not a valid JWT — use fallback
  }
  return DateTime.now().add(const Duration(hours: 24));
}
