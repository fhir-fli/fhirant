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

/// The JWT header `typ` of an access token. RFC 9068 §4 (rfc-editor.org
/// txt, read 2026-11-21): "The resource server MUST verify that the "typ"
/// header value is "at+jwt" or "application/at+jwt" and reject tokens
/// carrying any other value." A refresh token keeps
/// the library's default `JWT`, so neither passes for the other.
const String accessTokenType = 'at+jwt';

/// Service for generating and verifying JWT tokens.
///
/// A token names its account by [User.accountKey] in `sub`, and carries
/// nothing else about the account: the role, the patient context and the
/// held scopes are read from the account at every request (auth
/// middleware). RFC 9068 §2.2 (read 2026-11-21) lists iss, exp, aud, sub,
/// client_id, iat and jti as REQUIRED. Each token used to carry `userId`,
/// `username` and `role` and no iss, aud or sub; the account was found by
/// `userId`, which restarts at 1 in every store, and the role was the
/// token's. Two stores sharing the signing secret took each other's tokens
/// for whoever held the same number, with the issuing store's role: probe
/// of 2026-11-21, another store's id 16, an administrator, opened this
/// store's `/admin/users` as its id 16, a clinician (REVIEW-2026-10-17,
/// OWASP ASVS 5.0.0 V10.3.3; `tool/review_2026-10-17/asvs_notprobed.py`).
///
/// [issuer] is the operator's `--base-url`. With it, every token carries it
/// as `iss` and `aud`, and one carrying any other value, or none, is
/// refused (RFC 9068 §4: the `iss` "MUST exactly match", and a token whose
/// `aud` does not contain this server "MUST be rejected"). Without it (the
/// phone, whose address changes with each network) neither is written nor
/// checked, and `sub` alone keeps another store's token off this store's
/// accounts. `client_id` is written when the session came from an OAuth
/// client (`/auth/authorize`); `/auth/login` has none, and RFC 9068 names
/// no value for that case, so none is written.
class JwtService {
  /// Creates a JwtService with the given secret and optional token lifetimes.
  JwtService(
    this._secret, {
    String? issuer,
    Duration tokenLifetime = const Duration(hours: 8),
    Duration refreshTokenLifetime = const Duration(days: 7),
  })  : _issuer = issuer,
        _tokenLifetime = tokenLifetime,
        _refreshTokenLifetime = refreshTokenLifetime;
  final String _secret;
  final String? _issuer;
  final Duration _tokenLifetime;
  final Duration _refreshTokenLifetime;

  /// The one way a session is minted: an access token and a refresh token
  /// for [user], naming it by its account key and carrying its current
  /// token generation, [scopes] and, from an OAuth client, [clientId].
  /// Before 2026-09-22 the pair was minted at five sites, and
  /// registration's carried no generation.
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
    String? clientId,
  }) {
    final access = generateToken(
      subject: user.accountKey,
      scopes: scopes,
      generation: user.tokenGeneration,
      notAfter: notAfter,
      clientId: clientId,
    );
    final claims = JWT.decode(access).payload as Map<String, dynamic>;
    return (
      access: access,
      refresh: generateRefreshToken(
        subject: user.accountKey,
        scopes: scopes,
        generation: user.tokenGeneration,
        notAfter: notAfter,
        clientId: clientId,
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

  Map<String, dynamic> _claims({
    required String subject,
    required List<String>? scopes,
    required int generation,
    required String? clientId,
  }) =>
      {
        if (_issuer != null) 'iss': _issuer,
        if (_issuer != null) 'aud': _issuer,
        'sub': subject,
        if (clientId != null) 'client_id': clientId,
        if (scopes != null) 'scope': scopes.join(' '),
        // The account's token generation at issue (auth/token_bound.dart).
        'gen': generation,
        'jti': _newJti(),
      };

  /// An access token for the account whose key is [subject]
  /// ([User.accountKey]). Sessions come from [issueSession]; this is public
  /// for tests that need a token of a given shape.
  String generateToken({
    required String subject,
    List<String>? scopes,
    int generation = 0,
    DateTime? notAfter,
    String? clientId,
  }) {
    final jwt = JWT(
      _claims(
        subject: subject,
        scopes: scopes,
        generation: generation,
        clientId: clientId,
      ),
      header: {'typ': accessTokenType},
    );
    return jwt.sign(
      SecretKey(_secret),
      expiresIn: _capped(_tokenLifetime, notAfter),
    );
  }

  /// A refresh token: the access token's claims plus `token_type: refresh`,
  /// with the longer lifetime.
  String generateRefreshToken({
    required String subject,
    List<String>? scopes,
    int generation = 0,
    DateTime? notAfter,
    String? clientId,
  }) {
    final jwt = JWT({
      ..._claims(
        subject: subject,
        scopes: scopes,
        generation: generation,
        clientId: clientId,
      ),
      'token_type': 'refresh',
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
  ///
  /// A token must carry `exp`. The library checks `exp` only when it is
  /// present, so a token signed with the real secret but no `exp` never
  /// expired (REVIEW-2026-10-17 asvs_probes, "token: no exp", 200). RFC 9068
  /// §2.2 (read 2026-11-10, rfc-editor.org txt): "exp REQUIRED"; §4: "The
  /// current time MUST be before the time represented by the "exp" claim."
  /// OWASP ASVS 5.0.0 V9.2.1 (flat.json, read 2026-11-10): "the claims 'nbf'
  /// and 'exp' must be verified." Every token this service signs has one.
  Map<String, dynamic>? verifyToken(String token) {
    try {
      if (_header(token)?['alg'] != _pinnedAlgorithm.name) return null;
      final jwt = JWT.verify(
        token,
        SecretKey(_secret),
        // The `typ` is checked by the caller: an access token's is at+jwt.
        checkHeaderType: false,
      );
      final payload = jwt.payload;
      if (payload is! Map<String, dynamic>) return null;
      if (payload['exp'] is! num) return null;
      if (payload['sub'] is! String) return null;
      if (!_fromThisIssuer(payload)) return null;
      return payload;
    } catch (_) {
      return null;
    }
  }

  /// With an [_issuer] set, whether `iss` is exactly it and `aud` contains
  /// it (RFC 9068 §4). Without one, every token passes here.
  bool _fromThisIssuer(Map<String, dynamic> payload) {
    final issuer = _issuer;
    if (issuer == null) return true;
    if (payload['iss'] != issuer) return false;
    final aud = payload['aud'];
    return aud == issuer || (aud is List && aud.contains(issuer));
  }

  /// A JWT's decoded header, or null if the token is malformed.
  static Map<String, dynamic>? _header(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final headerJson =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[0])));
      final header = jsonDecode(headerJson);
      return header is Map<String, dynamic> ? header : null;
    } catch (_) {
      return null;
    }
  }

  /// Verifies an ACCESS token: a valid signature, header `typ` at+jwt, and
  /// a payload that is not a refresh token. A refresh token presented as a
  /// Bearer credential is refused here, not merely at the resource-scope
  /// check.
  Map<String, dynamic>? verifyAccessToken(String token) {
    final payload = verifyToken(token);
    if (payload == null) return null;
    if (_header(token)?['typ'] != accessTokenType) return null;
    if (payload['token_type'] == 'refresh') return null;
    return payload;
  }

  /// Verifies a refresh token. Returns the payload only if it's a valid
  /// refresh token (has `token_type: refresh`). Returns null otherwise.
  Map<String, dynamic>? verifyRefreshToken(String token) {
    final payload = verifyToken(token);
    if (payload == null) return null;
    if (_header(token)?['typ'] == accessTokenType) return null;
    if (payload['token_type'] != 'refresh') return null;
    return payload;
  }
}
