import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/jwt_service.dart';
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
/// - `grant_type=authorization_code` — exchange an authorization code for tokens
Future<Response> refreshHandler(
    Request request, FhirAntDb dbInterface, JwtService jwtService) async {
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
      return _handleAuthorizationCodeGrant(body, dbInterface, jwtService);
    }

    if (grantType == 'refresh_token') {
      return _handleRefreshTokenGrant(body, jwtService, dbInterface);
    }

    return Response(400,
        body: jsonEncode({
          'error': 'unsupported_grant_type',
          'error_description':
              'Supported grant types: authorization_code, refresh_token',
        }));
  } catch (e) {
    return Response.internalServerError(
        body: jsonEncode({
      'error': 'server_error',
      'error_description': 'Token exchange failed: $e',
    }));
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
    return Response(400,
        body: jsonEncode({
          'error': 'invalid_request',
          'error_description': 'code is required',
        }));
  }

  if (redirectUri == null || redirectUri.isEmpty) {
    return Response(400,
        body: jsonEncode({
          'error': 'invalid_request',
          'error_description': 'redirect_uri is required',
        }));
  }

  // Look up the authorization code
  final authCode = await dbInterface.getAuthorizationCode(code);
  if (authCode == null) {
    return Response(400,
        body: jsonEncode({
          'error': 'invalid_grant',
          'error_description': 'Authorization code not found',
        }));
  }

  // Check if already used
  if (authCode.used) {
    return Response(400,
        body: jsonEncode({
          'error': 'invalid_grant',
          'error_description': 'Authorization code has already been used',
        }));
  }

  // Check expiration
  if (DateTime.now().isAfter(authCode.expiresAt)) {
    await dbInterface.markAuthorizationCodeUsed(code);
    return Response(400,
        body: jsonEncode({
          'error': 'invalid_grant',
          'error_description': 'Authorization code has expired',
        }));
  }

  // Validate redirect_uri matches
  if (authCode.redirectUri != redirectUri) {
    return Response(400,
        body: jsonEncode({
          'error': 'invalid_grant',
          'error_description': 'redirect_uri does not match',
        }));
  }

  // Validate client_id matches (if provided)
  if (clientId != null && authCode.clientId != clientId) {
    return Response(400,
        body: jsonEncode({
          'error': 'invalid_grant',
          'error_description': 'client_id does not match',
        }));
  }

  // Verify PKCE if code_challenge was stored
  if (authCode.codeChallenge != null &&
      authCode.codeChallengeMethod != null) {
    if (codeVerifier == null || codeVerifier.isEmpty) {
      return Response(400,
          body: jsonEncode({
            'error': 'invalid_request',
            'error_description':
                'code_verifier is required (PKCE was used during authorization)',
          }));
    }
    if (!Pkce.verifyCodeChallenge(
      codeVerifier: codeVerifier,
      codeChallenge: authCode.codeChallenge!,
      codeChallengeMethod: authCode.codeChallengeMethod!,
    )) {
      return Response(400,
          body: jsonEncode({
            'error': 'invalid_grant',
            'error_description': 'PKCE code_verifier does not match',
          }));
    }
  }

  // Mark code as used
  await dbInterface.markAuthorizationCodeUsed(code);

  // Look up the user
  final user = await dbInterface.getUserById(authCode.userId);
  if (user == null) {
    return Response(400,
        body: jsonEncode({
          'error': 'invalid_grant',
          'error_description': 'User no longer exists',
        }));
  }

  if (!user.active) {
    return Response(403,
        body: jsonEncode({
          'error': 'invalid_grant',
          'error_description': 'Account is deactivated',
        }));
  }

  // Compute effective scopes
  final List<String> scopes;
  if (authCode.scope.isNotEmpty) {
    scopes = authCode.scope.split(' ');
  } else if (user.scopes != null && user.scopes!.isNotEmpty) {
    scopes =
        (jsonDecode(user.scopes!) as List<dynamic>).cast<String>();
  } else {
    scopes = SmartScopeEnforcer.defaultScopesForRole(user.role);
  }

  // Generate tokens
  final accessToken = jwtService.generateToken(
    userId: user.id,
    username: user.username,
    role: user.role,
    scopes: scopes,
  );

  final refreshToken = jwtService.generateRefreshToken(
    userId: user.id,
    username: user.username,
    role: user.role,
    scopes: scopes,
  );

  return Response.ok(
    jsonEncode({
      'access_token': accessToken,
      'token_type': 'Bearer',
      'refresh_token': refreshToken,
      'scope': scopes.join(' '),
      'username': user.username,
      'role': user.role,
    }),
    headers: {'Content-Type': 'application/json'},
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
    return Response(400,
        body: jsonEncode({
          'error': 'invalid_request',
          'error_description': 'refresh_token is required',
        }));
  }

  // Check if the refresh token has been revoked
  final refreshHash = TokenHasher.hash(refreshToken);
  if (await dbInterface.isTokenRevoked(refreshHash)) {
    return Response(401,
        body: jsonEncode({
          'error': 'invalid_grant',
          'error_description': 'Refresh token has been revoked',
        }));
  }

  // Verify the refresh token
  final payload = jwtService.verifyRefreshToken(refreshToken);
  if (payload == null) {
    return Response(401,
        body: jsonEncode({
          'error': 'invalid_grant',
          'error_description': 'Refresh token is invalid or expired',
        }));
  }

  // Verify the user still exists and is active
  final userId = payload['userId'] as int?;
  final username = payload['username'] as String?;
  if (userId == null || username == null) {
    return Response(401,
        body: jsonEncode({
          'error': 'invalid_grant',
          'error_description': 'Invalid refresh token payload',
        }));
  }

  final user = await dbInterface.getUserByUsername(username);
  if (user == null || user.id != userId) {
    return Response(401,
        body: jsonEncode({
          'error': 'invalid_grant',
          'error_description': 'User no longer exists',
        }));
  }

  if (!user.active) {
    return Response(403,
        body: jsonEncode({
          'error': 'invalid_grant',
          'error_description': 'Account is deactivated',
        }));
  }

  // Extract scopes and patient context from the refresh token
  final scopeStr = payload['scope'] as String?;
  final scopes =
      scopeStr != null && scopeStr.isNotEmpty ? scopeStr.split(' ') : null;
  final patientId = payload['patient'] as String?;

  // Generate new access token
  final newAccessToken = jwtService.generateToken(
    userId: user.id,
    username: user.username,
    role: user.role,
    scopes: scopes,
    patientId: patientId,
  );

  // Generate new refresh token (rotation)
  final newRefreshToken = jwtService.generateRefreshToken(
    userId: user.id,
    username: user.username,
    role: user.role,
    scopes: scopes,
    patientId: patientId,
  );

  // Revoke the old refresh token (rotation revocation)
  final oldExpiresAt = _extractExpiresAt(refreshToken);
  await dbInterface.revokeToken(refreshHash, oldExpiresAt);

  return Response.ok(
    jsonEncode({
      'access_token': newAccessToken,
      'token_type': 'Bearer',
      'refresh_token': newRefreshToken,
      'scope': scopes?.join(' ') ?? '',
      'username': user.username,
      'role': user.role,
      if (scopes != null) 'scopes': scopes,
      if (patientId != null) 'patient': patientId,
    }),
    headers: {'Content-Type': 'application/json'},
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
          (payload['exp'] as num).toInt() * 1000);
    }
  } catch (_) {
    // Not a valid JWT — use fallback
  }
  return DateTime.now().add(const Duration(hours: 24));
}
