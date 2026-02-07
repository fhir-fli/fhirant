import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Utility class for hashing and verifying passwords using HMAC-SHA256.
class PasswordHasher {
  /// Generates a cryptographically secure random salt (32 bytes, base64url).
  static String generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Hashes a password with the given salt using HMAC-SHA256.
  static String hashPassword(String password, String salt) {
    final key = utf8.encode(salt);
    final data = utf8.encode(password);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(data);
    return digest.toString();
  }

  /// Verifies a password against a stored hash using constant-time comparison.
  static bool verifyPassword(
      String password, String salt, String storedHash) {
    final computedHash = hashPassword(password, salt);
    if (computedHash.length != storedHash.length) return false;
    var result = 0;
    for (var i = 0; i < computedHash.length; i++) {
      result |= computedHash.codeUnitAt(i) ^ storedHash.codeUnitAt(i);
    }
    return result == 0;
  }
}
