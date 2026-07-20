import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

/// The one signing/verification algorithm this server accepts. Pinning it
/// (rather than trusting the `alg` header of an incoming token) closes
/// algorithm-substitution attacks — most importantly a forged token with
/// `alg: none`, and HMAC/RSA confusion.
const JWTAlgorithm _pinnedAlgorithm = JWTAlgorithm.HS256;

/// Service for generating and verifying JWT tokens.
class JwtService {
  /// Creates a JwtService with the given secret and optional token lifetimes.
  JwtService(
    this._secret, {
    Duration tokenLifetime = const Duration(hours: 8),
    Duration refreshTokenLifetime = const Duration(days: 7),
  })  : _tokenLifetime = tokenLifetime,
        _refreshTokenLifetime = refreshTokenLifetime;
  final String _secret;
  final Duration _tokenLifetime;
  final Duration _refreshTokenLifetime;

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
  ///
  /// The token's declared algorithm must match [_pinnedAlgorithm]; this is
  /// checked from the header before signature verification so a token claiming
  /// `alg: none` (or any other algorithm) is rejected outright rather than
  /// handed to the library's alg-dispatch.
  Map<String, dynamic>? verifyToken(String token) {
    try {
      if (_headerAlgorithm(token) != _pinnedAlgorithm.name) return null;
      final jwt = JWT.verify(token, SecretKey(_secret));
      return jwt.payload as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Reads the `alg` value from a JWT's header segment, or null if the token
  /// is malformed.
  static String? _headerAlgorithm(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final headerJson =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[0])));
      final header = jsonDecode(headerJson);
      if (header is! Map<String, dynamic>) return null;
      final alg = header['alg'];
      return alg is String ? alg : null;
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
