import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

/// Service for generating and verifying JWT tokens.
class JwtService {
  final String _secret;
  final Duration _tokenLifetime;

  /// Creates a JwtService with the given secret and optional token lifetime.
  JwtService(this._secret, {Duration tokenLifetime = const Duration(hours: 8)})
      : _tokenLifetime = tokenLifetime;

  /// Generates a signed JWT containing user claims.
  String generateToken({
    required int userId,
    required String username,
    required String role,
    List<String>? scopes,
  }) {
    final jwt = JWT({
      'userId': userId,
      'username': username,
      'role': role,
      if (scopes != null) 'scope': scopes.join(' '),
    });
    return jwt.sign(
      SecretKey(_secret),
      expiresIn: _tokenLifetime,
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
}
