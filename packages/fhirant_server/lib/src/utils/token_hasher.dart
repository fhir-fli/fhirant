import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Utility for hashing tokens before storage in the revocation table.
class TokenHasher {
  TokenHasher._();

  /// Returns the SHA-256 hex digest of [token].
  static String hash(String token) =>
      sha256.convert(utf8.encode(token)).toString();
}
