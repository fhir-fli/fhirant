import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/token_hasher.dart';
import 'package:shelf/shelf.dart';

/// Handler for POST /auth/revoke (RFC 7009 token revocation).
///
/// Accepts `token` in JSON or form-encoded body. Always returns 200 per
/// RFC 7009 (the server MUST respond with 200 even for invalid tokens).
/// Returns 400 only when the `token` field is completely missing.
Future<Response> revokeHandler(Request request, FhirAntDb dbInterface) async {
  try {
    final body = await _parseBody(request);

    final token = body['token'] as String?;
    if (token == null || token.isEmpty) {
      return Response(400,
          body: jsonEncode({
            'error': 'invalid_request',
            'error_description': 'token parameter is required',
          }),
          headers: {'Content-Type': 'application/json'});
    }

    final tokenHash = TokenHasher.hash(token);
    final expiresAt = _extractExpiresAt(token);

    await dbInterface.revokeToken(tokenHash, expiresAt);

    return Response.ok(
      jsonEncode({'status': 'revoked'}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
        body: jsonEncode({
      'error': 'server_error',
      'error_description': 'Revocation failed: $e',
    }));
  }
}

/// Handler for POST /auth/logout.
///
/// Revokes the Bearer token from the Authorization header and optionally
/// a `refresh_token` from the request body.
Future<Response> logoutHandler(Request request, FhirAntDb dbInterface) async {
  try {
    // Revoke the access token from the Authorization header
    final authHeader = request.headers['authorization'];
    if (authHeader != null && authHeader.startsWith('Bearer ')) {
      final accessToken = authHeader.substring(7);
      final tokenHash = TokenHasher.hash(accessToken);
      final expiresAt = _extractExpiresAt(accessToken);
      await dbInterface.revokeToken(tokenHash, expiresAt);
    }

    // Optionally revoke a refresh token from the body
    final bodyStr = await request.readAsString();
    if (bodyStr.isNotEmpty) {
      final body = _tryParseBody(bodyStr);
      final refreshToken = body['refresh_token'] as String?;
      if (refreshToken != null && refreshToken.isNotEmpty) {
        final refreshHash = TokenHasher.hash(refreshToken);
        final expiresAt = _extractExpiresAt(refreshToken);
        await dbInterface.revokeToken(refreshHash, expiresAt);
      }
    }

    return Response.ok(
      jsonEncode({'status': 'logged_out'}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
        body: jsonEncode({
      'error': 'server_error',
      'error_description': 'Logout failed: $e',
    }));
  }
}

/// Extract expiration from a JWT without signature verification.
/// Falls back to now + 24 hours if the token can't be decoded.
DateTime _extractExpiresAt(String token, [Duration fallback = const Duration(hours: 24)]) {
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
  return DateTime.now().add(fallback);
}

/// Parse JSON or form-encoded body.
Future<Map<String, dynamic>> _parseBody(Request request) async {
  final bodyStr = await request.readAsString();
  return _tryParseBody(bodyStr);
}

/// Try JSON first, fall back to form-encoded.
Map<String, dynamic> _tryParseBody(String bodyStr) {
  try {
    return jsonDecode(bodyStr) as Map<String, dynamic>;
  } catch (_) {
    return Map<String, dynamic>.from(Uri.splitQueryString(bodyStr));
  }
}
