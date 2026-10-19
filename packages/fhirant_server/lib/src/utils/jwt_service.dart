import 'dart:convert';
import 'dart:math';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:fhirant_db/fhirant_db.dart' show User;

/// The one signing/verification algorithm this server accepts. Pinning it
/// (rather than trusting the `alg` header of an incoming token) closes
/// algorithm-substitution attacks — most importantly a forged token with
/// `alg: none`, and HMAC/RSA confusion.
const JWTAlgorithm _pinnedAlgorithm = JWTAlgorithm.HS256;

final Random _random = Random.secure();

/// A fresh `jti` (RFC 7519 §4.1.7, read 2026-10-18: the claim "provides a
/// unique identifier for the JWT"): 128 random bits, base64url. Without it
/// two sessions of one account minted in the same second were the same
/// string, so revoking one by its hash revoked the other (REVIEW-2026-10-17
/// finding 5).
String _newJti() => base64Url
    .encode(List<int>.generate(16, (_) => _random.nextInt(256)))
    .replaceAll('=', '');

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
  /// The one way a session is minted: an access token and a refresh token
  /// for [user], carrying its id, name, role, patient context and current
  /// token generation, and [scopes]. Before 2026-09-22 the pair was minted
  /// at five sites, and registration's carried no generation.
  ///
  /// [notAfter] caps both tokens' lifetimes: a refresh passes the presented
  /// refresh token's own expiry, so the session ends where the login set it
  /// however often it is refreshed. OWASP ASVS 5.0.0 V10.4.8 (read
  /// 2026-10-17): "refresh tokens have an absolute expiration, including if
  /// sliding refresh token expiration is applied"; each rotation used to
  /// grant a fresh 7 days (REVIEW-2026-10-17 finding 17).
  ///
  /// [expiresIn] is the access token's lifetime in seconds, read from its
  /// own `exp` and `iat`, for the token reply's `expires_in` (SMART App
  /// Launch STU 2.2 app-launch.html, read 2026-10-18: "required" in the
  /// refresh response, "recommended" in the access token response;
  /// REVIEW-2026-10-17, smaller list).
  ({String access, String refresh, int expiresIn}) issueSession(
    User user, {
    required List<String> scopes,
    DateTime? notAfter,
  }) {
    final access = generateToken(
      userId: user.id,
      username: user.username,
      role: user.role,
      scopes: scopes,
      patientId: user.patientId,
      generation: user.tokenGeneration,
      notAfter: notAfter,
    );
    final claims = JWT.decode(access).payload as Map<String, dynamic>;
    return (
      access: access,
      refresh: generateRefreshToken(
        userId: user.id,
        username: user.username,
        role: user.role,
        scopes: scopes,
        patientId: user.patientId,
        generation: user.tokenGeneration,
        notAfter: notAfter,
      ),
      expiresIn: (claims['exp'] as int) - (claims['iat'] as int),
    );
  }

  /// [lifetime], shortened so that it ends no later than [notAfter].
  static Duration _capped(Duration lifetime, DateTime? notAfter) {
    if (notAfter == null) return lifetime;
    final left = notAfter.difference(DateTime.now());
    return left < lifetime ? left : lifetime;
  }

  String generateToken({
    required int userId,
    required String username,
    required String role,
    List<String>? scopes,
    String? patientId,
    int generation = 0,
    DateTime? notAfter,
  }) {
    final jwt = JWT({
      'userId': userId,
      'username': username,
      'role': role,
      if (scopes != null) 'scope': scopes.join(' '),
      if (patientId != null) 'patient': patientId,
      // The account's token generation at issue (auth/token_bound.dart).
      'gen': generation,
      'jti': _newJti(),
    });
    return jwt.sign(
      SecretKey(_secret),
      expiresIn: _capped(_tokenLifetime, notAfter),
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
    int generation = 0,
    DateTime? notAfter,
  }) {
    final jwt = JWT({
      'userId': userId,
      'username': username,
      'role': role,
      'token_type': 'refresh',
      if (scopes != null) 'scope': scopes.join(' '),
      if (patientId != null) 'patient': patientId,
      'gen': generation,
      'jti': _newJti(),
    });
    return jwt.sign(
      SecretKey(_secret),
      expiresIn: _capped(_refreshTokenLifetime, notAfter),
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

  /// Verifies an ACCESS token: a valid signature whose payload is not a
  /// refresh token. A refresh token presented as a Bearer credential is
  /// refused here, not merely at the resource-scope check.
  Map<String, dynamic>? verifyAccessToken(String token) {
    final payload = verifyToken(token);
    if (payload == null) return null;
    if (payload['token_type'] == 'refresh') return null;
    return payload;
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
