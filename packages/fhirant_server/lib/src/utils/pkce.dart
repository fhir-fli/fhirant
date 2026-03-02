import 'dart:convert';

import 'package:crypto/crypto.dart';

/// PKCE (Proof Key for Code Exchange) helper for OAuth 2.0.
///
/// Implements RFC 7636 code_challenge verification using S256 method.
class Pkce {
  Pkce._();

  /// Verify that the code_verifier matches the stored code_challenge.
  ///
  /// Supports `S256` (SHA-256) and `plain` methods.
  /// Returns `true` if the verifier matches the challenge.
  static bool verifyCodeChallenge({
    required String codeVerifier,
    required String codeChallenge,
    required String codeChallengeMethod,
  }) {
    switch (codeChallengeMethod) {
      case 'S256':
        final computed = _computeS256Challenge(codeVerifier);
        return computed == codeChallenge;
      case 'plain':
        return codeVerifier == codeChallenge;
      default:
        return false;
    }
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
