import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Password hashing and verification.
///
/// New hashes use PBKDF2-HMAC-SHA256 with a high iteration count — a slow,
/// deliberately expensive key-derivation function, so that if the (encrypted)
/// database ever leaks, offline guessing of passwords is costly. It is built
/// on the `crypto` package (pure Dart, no native dependency) so it runs the
/// same on-device and headless, offline.
///
/// Older accounts were stored as a single HMAC-SHA256 digest; [verifyPassword]
/// still accepts those so existing logins keep working, and [needsRehash]
/// reports when such a hash should be upgraded (the login path can re-hash on
/// a successful sign-in).
class PasswordHasher {
  PasswordHasher._();

  /// Iteration count for new PBKDF2 hashes. Chosen to be meaningfully
  /// expensive for offline guessing while staying acceptable for an occasional
  /// login on a phone.
  static const int pbkdf2Iterations = 120000;

  /// Derived-key length in bytes (SHA-256 output size).
  static const int _dkLen = 32;

  /// Prefix tagging the PBKDF2 format: `pbkdf2$<iterations>$<hexDigest>`.
  static const _pbkdf2Prefix = 'pbkdf2';

  /// Generates a cryptographically secure random salt (32 bytes, base64url).
  static String generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Hashes [password] with [salt] using PBKDF2-HMAC-SHA256, returning a
  /// self-describing `pbkdf2$<iterations>$<hexDigest>` string.
  static String hashPassword(String password, String salt) {
    final dk = _pbkdf2(
      utf8.encode(password),
      utf8.encode(salt),
      pbkdf2Iterations,
      _dkLen,
    );
    return '$_pbkdf2Prefix\$$pbkdf2Iterations\$${_toHex(dk)}';
  }

  /// Verifies [password] against a [storedHash] (with its [salt]) using a
  /// constant-time comparison. Accepts both the current PBKDF2 format and the
  /// legacy single-round HMAC-SHA256 format.
  static bool verifyPassword(String password, String salt, String storedHash) {
    if (storedHash.startsWith('$_pbkdf2Prefix\$')) {
      final parts = storedHash.split(r'$');
      if (parts.length != 3) return false;
      final iterations = int.tryParse(parts[1]);
      if (iterations == null || iterations < 1) return false;
      final dk = _pbkdf2(
        utf8.encode(password),
        utf8.encode(salt),
        iterations,
        _dkLen,
      );
      return _constantTimeEquals(_toHex(dk), parts[2]);
    }

    // Legacy: single-round HMAC-SHA256 hex digest.
    final legacy = Hmac(sha256, utf8.encode(salt))
        .convert(utf8.encode(password))
        .toString();
    return _constantTimeEquals(legacy, storedHash);
  }

  /// Whether [storedHash] is in an outdated format (legacy HMAC, or PBKDF2 with
  /// fewer iterations than the current target) and should be re-hashed on the
  /// next successful login.
  static bool needsRehash(String storedHash) {
    if (!storedHash.startsWith('$_pbkdf2Prefix\$')) return true;
    final parts = storedHash.split(r'$');
    if (parts.length != 3) return true;
    final iterations = int.tryParse(parts[1]);
    return iterations == null || iterations < pbkdf2Iterations;
  }

  /// PBKDF2 (RFC 2898) with HMAC-SHA256. For [dkLen] equal to the HMAC output
  /// size (32 bytes) only the first derived block is needed.
  static List<int> _pbkdf2(
    List<int> password,
    List<int> salt,
    int iterations,
    int dkLen,
  ) {
    final hmac = Hmac(sha256, password);

    // U1 = PRF(password, salt || INT_32_BE(1)).
    final salted = Uint8List(salt.length + 4)
      ..setRange(0, salt.length, salt)
      ..[salt.length + 3] = 1; // block index 1, big-endian
    var u = hmac.convert(salted).bytes;
    final result = Uint8List.fromList(u);

    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return result.sublist(0, dkLen);
  }

  static String _toHex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  /// Constant-time string comparison to avoid leaking match length via timing.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}
