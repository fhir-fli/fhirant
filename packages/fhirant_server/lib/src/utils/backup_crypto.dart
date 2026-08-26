import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// Passphrase-based encryption for database exports.
///
/// A backup is the one artefact that has to leave the device. The database
/// itself is encrypted with a key sealed in platform secure storage, which is
/// exactly what stops that key — and therefore the database — moving to a
/// replacement device. So the export cannot inherit that protection, and until
/// this existed the only way to carry a record to another phone was to write
/// it out in the clear.
///
/// The envelope here is self-describing and carries no key material: the
/// operator's passphrase plus the file is everything needed to restore, and
/// nothing else is. That is what makes the file safe to move by any means to
/// hand — a network transfer, or an SD card, which in a disaster setting is
/// often the only one available.
///
/// PBKDF2-HMAC-SHA256 for derivation (the same pure-Dart primitive the
/// password hasher uses, so there is no native dependency and it behaves the
/// same on-device and headless) and AES-256-GCM for encryption, so a wrong
/// passphrase or a tampered file fails the authentication tag rather than
/// silently producing garbage.
class BackupCrypto {
  BackupCrypto._();

  /// Envelope format version. Present so a future format can be recognised
  /// rather than mis-parsed.
  static const int formatVersion = 1;

  /// Iteration count for deriving the file key.
  ///
  /// Higher than the login hash's 120,000: a login runs on every sign-in and
  /// has to stay responsive, whereas a backup is derived once per export or
  /// restore, and the file it protects may sit on removable media for a long
  /// time where an attacker can guess against it at leisure.
  static const int kdfIterations = 210000;

  static const int _keyLengthBytes = 32; // AES-256
  static const int _saltLengthBytes = 16;
  static const int _ivLengthBytes = 12; // 96-bit nonce, as GCM expects
  static const int _macLengthBits = 128;

  static const String _kdfAlgorithm = 'PBKDF2-HMAC-SHA256';
  static const String _cipherAlgorithm = 'AES-256-GCM';

  /// Encrypts [plaintext] under [passphrase], returning the JSON envelope.
  ///
  /// A fresh salt and nonce are drawn per call, so encrypting the same
  /// database twice never produces the same bytes and never reuses a nonce
  /// under the same key.
  static String encrypt(String plaintext, String passphrase) {
    if (passphrase.isEmpty) {
      throw ArgumentError.value(passphrase, 'passphrase', 'must not be empty');
    }

    final salt = _randomBytes(_saltLengthBytes);
    final iv = _randomBytes(_ivLengthBytes);
    final key = _deriveKey(passphrase, salt, kdfIterations);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), _macLengthBits, iv, Uint8List(0)),
      );
    final ciphertext = cipher.process(
      Uint8List.fromList(utf8.encode(plaintext)),
    );

    return jsonEncode({
      'fhirantBackup': formatVersion,
      'kdf': {
        'alg': _kdfAlgorithm,
        'iterations': kdfIterations,
        'salt': base64Url.encode(salt),
      },
      'cipher': {
        'alg': _cipherAlgorithm,
        'iv': base64Url.encode(iv),
      },
      'ciphertext': base64.encode(ciphertext),
    });
  }

  /// Decrypts an envelope produced by [encrypt].
  ///
  /// Throws [BackupDecryptionException] if the passphrase is wrong, the file
  /// has been altered, or the envelope is not one this version understands.
  /// A wrong passphrase and a tampered file are deliberately indistinguishable
  /// to the caller: both mean "this did not authenticate".
  static String decrypt(String envelopeJson, String passphrase) {
    final Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(envelopeJson) as Map<String, dynamic>;
    } catch (_) {
      throw const BackupDecryptionException('Not a backup envelope');
    }

    final version = envelope['fhirantBackup'];
    if (version != formatVersion) {
      throw BackupDecryptionException(
        'Unsupported backup format: $version (this server writes '
        '$formatVersion)',
      );
    }

    final kdf = envelope['kdf'];
    final cipherSpec = envelope['cipher'];
    if (kdf is! Map || cipherSpec is! Map) {
      throw const BackupDecryptionException('Malformed backup envelope');
    }
    if (kdf['alg'] != _kdfAlgorithm || cipherSpec['alg'] != _cipherAlgorithm) {
      throw BackupDecryptionException(
        'Unsupported algorithms: ${kdf['alg']} / ${cipherSpec['alg']}',
      );
    }

    final iterations = kdf['iterations'];
    if (iterations is! int || iterations < 1) {
      throw const BackupDecryptionException('Malformed KDF iteration count');
    }

    final Uint8List salt;
    final Uint8List iv;
    final Uint8List ciphertext;
    try {
      salt = base64Url.decode(kdf['salt'] as String);
      iv = base64Url.decode(cipherSpec['iv'] as String);
      ciphertext = base64.decode(envelope['ciphertext'] as String);
    } catch (_) {
      throw const BackupDecryptionException('Malformed backup envelope');
    }

    final key = _deriveKey(passphrase, salt, iterations);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(KeyParameter(key), _macLengthBits, iv, Uint8List(0)),
      );

    final Uint8List plaintext;
    try {
      plaintext = cipher.process(ciphertext);
    } catch (_) {
      // GCM tag mismatch: wrong passphrase, or the file was altered.
      throw const BackupDecryptionException(
        'Could not decrypt the backup: wrong passphrase, or the file has been '
        'altered',
      );
    }

    try {
      return utf8.decode(plaintext);
    } catch (_) {
      throw const BackupDecryptionException('Decrypted content is not text');
    }
  }

  /// Whether [content] looks like an envelope rather than a bare Bundle.
  ///
  /// Used by restore so it can tell an operator "this needs a passphrase"
  /// instead of failing to parse it as FHIR.
  static bool isEnvelope(String content) {
    try {
      final decoded = jsonDecode(content);
      return decoded is Map && decoded.containsKey('fhirantBackup');
    } catch (_) {
      return false;
    }
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  /// PBKDF2-HMAC-SHA256, matching the construction in [PasswordHasher].
  static Uint8List _deriveKey(String passphrase, Uint8List salt, int rounds) {
    final hmac = Hmac(sha256, utf8.encode(passphrase));
    final out = BytesBuilder();
    var block = 1;
    while (out.length < _keyLengthBytes) {
      final blockIndex = Uint8List(4)
        ..[0] = block >> 24
        ..[1] = (block >> 16) & 0xff
        ..[2] = (block >> 8) & 0xff
        ..[3] = block & 0xff;

      var u = Uint8List.fromList(hmac.convert([...salt, ...blockIndex]).bytes);
      final acc = Uint8List.fromList(u);
      for (var i = 1; i < rounds; i++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (var j = 0; j < acc.length; j++) {
          acc[j] ^= u[j];
        }
      }
      out.add(acc);
      block++;
    }
    return Uint8List.fromList(out.toBytes().sublist(0, _keyLengthBytes));
  }
}

/// Raised when a backup envelope cannot be decrypted or is not understood.
class BackupDecryptionException implements Exception {
  const BackupDecryptionException(this.message);

  final String message;

  @override
  String toString() => 'BackupDecryptionException: $message';
}
