import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:shelf/shelf.dart';

/// Handler for token refresh. Accepts a refresh token and returns a new
/// access token + refresh token pair.
///
/// POST /auth/token
/// Body: { "grant_type": "refresh_token", "refresh_token": "<token>" }
Future<Response> refreshHandler(
    Request request, FhirAntDb dbInterface, JwtService jwtService) async {
  try {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;

    final grantType = body['grant_type'] as String?;
    if (grantType != 'refresh_token') {
      return Response(400,
          body: jsonEncode(
              {'error': 'unsupported_grant_type',
               'error_description': 'Only grant_type=refresh_token is supported'}));
    }

    final refreshToken = body['refresh_token'] as String?;
    if (refreshToken == null || refreshToken.isEmpty) {
      return Response(400,
          body: jsonEncode(
              {'error': 'invalid_request',
               'error_description': 'refresh_token is required'}));
    }

    // Verify the refresh token
    final payload = jwtService.verifyRefreshToken(refreshToken);
    if (payload == null) {
      return Response(401,
          body: jsonEncode(
              {'error': 'invalid_grant',
               'error_description': 'Refresh token is invalid or expired'}));
    }

    // Verify the user still exists and is active
    final userId = payload['userId'] as int?;
    final username = payload['username'] as String?;
    if (userId == null || username == null) {
      return Response(401,
          body: jsonEncode(
              {'error': 'invalid_grant',
               'error_description': 'Invalid refresh token payload'}));
    }

    final user = await dbInterface.getUserByUsername(username);
    if (user == null || user.id != userId) {
      return Response(401,
          body: jsonEncode(
              {'error': 'invalid_grant',
               'error_description': 'User no longer exists'}));
    }

    if (!user.active) {
      return Response(403,
          body: jsonEncode(
              {'error': 'invalid_grant',
               'error_description': 'Account is deactivated'}));
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

    return Response.ok(
      jsonEncode({
        'token': newAccessToken,
        'refresh_token': newRefreshToken,
        'token_type': 'Bearer',
        'username': user.username,
        'role': user.role,
        if (scopes != null) 'scopes': scopes,
        if (patientId != null) 'patient': patientId,
      }),
    );
  } catch (e) {
    return Response.internalServerError(
        body: jsonEncode({'error': 'server_error',
                          'error_description': 'Token refresh failed: $e'}));
  }
}
