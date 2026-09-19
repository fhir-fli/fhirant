import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// Password hashing and verification.
///
/// New hashes are Argon2id at the OWASP Password Storage Cheat Sheet's
/// minimum (raw markdown read 2026-09-17, verbatim: "Use Argon2id with a
/// minimum configuration of 19 MiB of memory, an iteration count of 2, and 1
/// degree of parallelism"), computed off the calling isolate in
/// `Isolate.run`. They used to be PBKDF2-HMAC-SHA256 at 120,000 iterations,
/// a hand-written loop on the server isolate: 290–337 ms per login during
/// which nothing else was served, and a fifth of the cheat sheet's 600,000
/// (fhirant REVIEW-2026-09-17 A11). Argon2id at the minimum measured 150 ms
/// here against that loop's 277 (`tool/review_2026-09-17/fix_a11/`);
/// on a phone, unmeasured.
///
/// The two older formats, `pbkdf2$<iterations>$<hex>` and a bare
/// HMAC-SHA256 digest, still verify, and [needsRehash] reports them so a
/// successful login re-hashes the account.
///
/// Pure Dart (`pointycastle`, `crypto`): no native dependency, so it runs
/// the same on-device and headless, offline.
class PasswordHasher {
  PasswordHasher._();

  /// Argon2id memory, in KiB: 19 MiB.
  static const int argon2Memory = 19456;

  /// Argon2id iterations (passes).
  static const int argon2Iterations = 2;

  /// Argon2id lanes.
  static const int argon2Lanes = 1;

  /// The previous format's iteration count, kept for [needsRehash]'s
  /// reading of what a stored hash is.
  static const int pbkdf2Iterations = 120000;

  static const int _dkLen = 32;
  static const _argon2Prefix = 'argon2id';
  static const _pbkdf2Prefix = 'pbkdf2';

  /// The parameter field of a current hash.
  static const String _currentParameters =
      'm=$argon2Memory,t=$argon2Iterations,p=$argon2Lanes';

  /// Generates a cryptographically secure random salt (32 bytes, base64url).
  static String generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Hashes [password] with [salt], off this isolate, returning a
  /// self-describing `argon2id$m=<KiB>,t=<passes>,p=<lanes>$<hex>` string.
  static Future<String> hashPassword(String password, String salt) =>
      Isolate.run(() => hashPasswordSync(password, salt));

  /// [hashPassword] on the calling isolate. For tests and for a caller
  /// already off the main isolate.
  static String hashPasswordSync(String password, String salt) {
    final dk = _argon2(
      utf8.encode(password),
      utf8.encode(salt),
      memory: argon2Memory,
      iterations: argon2Iterations,
      lanes: argon2Lanes,
    );
    return '$_argon2Prefix\$$_currentParameters\$${_toHex(dk)}';
  }

  /// Verifies [password] against [storedHash] (with its [salt]), off this
  /// isolate, in constant time over the digest. Accepts the current Argon2id
  /// format, the PBKDF2 format and the legacy single-round HMAC-SHA256.
  static Future<bool> verifyPassword(
    String password,
    String salt,
    String storedHash,
  ) =>
      Isolate.run(() => verifyPasswordSync(password, salt, storedHash));

  /// [verifyPassword] on the calling isolate.
  static bool verifyPasswordSync(
    String password,
    String salt,
    String storedHash,
  ) {
    final parts = storedHash.split(r'$');
    if (parts.length == 3 && parts[0] == _argon2Prefix) {
      final parameters = _parseParameters(parts[1]);
      if (parameters == null) return false;
      final dk = _argon2(
        utf8.encode(password),
        utf8.encode(salt),
        memory: parameters.memory,
        iterations: parameters.iterations,
        lanes: parameters.lanes,
      );
      return _constantTimeEquals(_toHex(dk), parts[2]);
    }
    if (parts.length == 3 && parts[0] == _pbkdf2Prefix) {
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

  /// Whether [storedHash] is not a current hash (a legacy HMAC, a PBKDF2 at
  /// any iteration count, or Argon2id below the current parameters) and
  /// should be re-hashed on the next successful login.
  static bool needsRehash(String storedHash) {
    final parts = storedHash.split(r'$');
    if (parts.length != 3 || parts[0] != _argon2Prefix) return true;
    final parameters = _parseParameters(parts[1]);
    return parameters == null ||
        parameters.memory < argon2Memory ||
        parameters.iterations < argon2Iterations ||
        parameters.lanes < argon2Lanes;
  }

  static ({int memory, int iterations, int lanes})? _parseParameters(
    String field,
  ) {
    final values = <String, int>{};
    for (final part in field.split(',')) {
      final kv = part.split('=');
      if (kv.length != 2) return null;
      final v = int.tryParse(kv[1]);
      if (v == null || v < 1) return null;
      values[kv[0]] = v;
    }
    final m = values['m'];
    final t = values['t'];
    final p = values['p'];
    if (m == null || t == null || p == null) return null;
    return (memory: m, iterations: t, lanes: p);
  }

  static Uint8List _argon2(
    List<int> password,
    List<int> salt, {
    required int memory,
    required int iterations,
    required int lanes,
  }) {
    final generator = Argon2BytesGenerator()
      ..init(
        Argon2Parameters(
          Argon2Parameters.ARGON2_id,
          Uint8List.fromList(salt),
          desiredKeyLength: _dkLen,
          iterations: iterations,
          memory: memory,
          lanes: lanes,
        ),
      );
    return generator.process(Uint8List.fromList(password));
  }

  /// PBKDF2 (RFC 2898) with HMAC-SHA256, for the previous format. For
  /// [dkLen] equal to the HMAC output size (32 bytes) only the first derived
  /// block is needed.
  static List<int> _pbkdf2(
    List<int> password,
    List<int> salt,
    int iterations,
    int dkLen,
  ) {
    final hmac = Hmac(sha256, password);
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
