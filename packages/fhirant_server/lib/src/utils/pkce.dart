import 'dart:convert';

import 'package:crypto/crypto.dart';

/// PKCE (Proof Key for Code Exchange) helper for OAuth 2.0.
///
/// Implements RFC 7636 code_challenge verification with the S256 method
/// only. RFC 7636 §7.2 (read 2026-09-19, verbatim): "Because of this,
/// "plain" SHOULD NOT be used and exists only for compatibility with
/// deployed implementations where the request path is already protected."
/// `/auth/authorize` has refused `plain` since REVIEW-2026-09-06 finding
/// 10; this verifier accepted it anyway, so a stored code with that method
/// would have been honoured (REVIEW-2026-09-17 A16). Now no path does.
class Pkce {
  Pkce._();

  /// Verify that the code_verifier matches the stored code_challenge.
  ///
  /// Only `S256` verifies; `plain` and anything else return false.
  static bool verifyCodeChallenge({
    required String codeVerifier,
    required String codeChallenge,
    required String codeChallengeMethod,
  }) {
    if (codeChallengeMethod != 'S256') return false;
    return _computeS256Challenge(codeVerifier) == codeChallenge;
  }

  /// Compute the S256 code_challenge from a code_verifier.
  ///
  /// code_challenge = BASE64URL(SHA256(ASCII(code_verifier)))
  static String _computeS256Challenge(String codeVerifier) {
    final bytes = utf8.encode(codeVerifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }
}
