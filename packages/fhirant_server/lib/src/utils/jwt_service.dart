import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

/// Service for generating and verifying JWT tokens.
class JwtService {
  final String _secret;
  final Duration _tokenLifetime;
  final Duration _refreshTokenLifetime;

  /// Creates a JwtService with the given secret and optional token lifetimes.
  JwtService(
    this._secret, {
    Duration tokenLifetime = const Duration(hours: 8),
    Duration refreshTokenLifetime = const Duration(days: 7),
  })  : _tokenLifetime = tokenLifetime,
        _refreshTokenLifetime = refreshTokenLifetime;

  /// Generates a signed JWT containing user claims.
  String generateToken({
    required int userId,
    required String username,
    required String role,
    List<String>? scopes,
    String? patientId,
  }) {
    final jwt = JWT({
      'userId': userId,
      'username': username,
      'role': role,
      if (scopes != null) 'scope': scopes.join(' '),
      if (patientId != null) 'patient': patientId,
    });
    return jwt.sign(
      SecretKey(_secret),
      expiresIn: _tokenLifetime,
    );
  }

  /// Generates a refresh token with a longer lifetime.
  ///
  /// The refresh token contains the same user claims as the access token
  /// plus a `token_type: refresh` marker to distinguish it.
  String generateRefreshToken({
    required int userId,
    required String username,
    required String role,
    List<String>? scopes,
    String? patientId,
  }) {
    final jwt = JWT({
      'userId': userId,
      'username': username,
      'role': role,
      'token_type': 'refresh',
      if (scopes != null) 'scope': scopes.join(' '),
      if (patientId != null) 'patient': patientId,
    });
    return jwt.sign(
      SecretKey(_secret),
      expiresIn: _refreshTokenLifetime,
    );
  }

  /// Verifies a JWT token and returns its payload, or null if invalid/expired.
  Map<String, dynamic>? verifyToken(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(_secret));
      return jwt.payload as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Verifies a refresh token. Returns the payload only if it's a valid
  /// refresh token (has `token_type: refresh`). Returns null otherwise.
  Map<String, dynamic>? verifyRefreshToken(String token) {
    final payload = verifyToken(token);
    if (payload == null) return null;
    if (payload['token_type'] != 'refresh') return null;
    return payload;
  }
}
