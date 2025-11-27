import 'dart:convert';
import 'dart:math';
import 'package:basic_utils/basic_utils.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fhirant_logging/fhirant_logging.dart';

/// Secure Storage Service
class SecureStorageService {
  /// Encryption key for secure storage
  static const encryptionKey = 'fhirant_encryption_key';

  /// Private key for secure storage
  static const privateKeyKey = 'fhirant_private_key';

  /// Certificate key for secure storage
  static const certificateKey = 'fhirant_certificate_key';

  /// Secure storage key prefix for passkeys
  static const passkeyPrefix = 'fhirant_passkey_';

  /// FlutterSecureStorage instance
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();

  /// Save a passkey securely
  Future<void> storePasskey(String username, String credential) async {
    try {
      final key = '$passkeyPrefix$username';
      await secureStorage.write(key: key, value: credential);
      FhirantLogging().logInfo(
        'Passkey saved securely for user: $username.',
      );
    } catch (e) {
      FhirantLogging().logError(
        'Error saving passkey for user $username: $e',
      );
      rethrow;
    }
  }

  /// Retrieve a stored passkey securely
  Future<String?> getPasskey(String username) async {
    try {
      final key = '$passkeyPrefix$username';
      final credentials = await secureStorage.read(key: key);
      if (credentials == null) {
        FhirantLogging().logInfo('No passkey found for user $username.');
      }
      return credentials;
    } catch (e) {
      FhirantLogging().logError(
        'Error retrieving passkey for user $username: $e',
      );
      rethrow;
    }
  }

  /// Save the encryption key securely
  Future<void> saveEncryptionKey(String key) async {
    try {
      await secureStorage.write(key: encryptionKey, value: key);
      FhirantLogging().logInfo('Encryption key saved securely.');
    } catch (e) {
      FhirantLogging().logError('Error saving encryption key: $e');
      rethrow;
    }
  }

  /// Retrieve the encryption key securely
  Future<String?> getEncryptionKey() async {
    try {
      var key = await secureStorage.read(key: encryptionKey);

      if (key == null) {
        key = generateEncryptionKey();
        await secureStorage.write(key: encryptionKey, value: key);
        FhirantLogging().logInfo(
          'New encryption key generated and stored securely.',
        );
      }
      return key;
    } catch (e) {
      FhirantLogging().logError('Error retrieving encryption key: $e');
      rethrow;
    }
  }

  /// Generate a random encryption key (for first-time setup)
  String generateRandomKey() {
    return generateSecureRandomKey(256);
  }

  /// Save the private key securely
  Future<void> savePrivateKey(String key) async {
    try {
      await secureStorage.write(key: privateKeyKey, value: key);
      FhirantLogging().logInfo('Private key saved securely.');
    } catch (e) {
      FhirantLogging().logError('Error saving private key: $e');
      rethrow;
    }
  }

  /// Save the certificate securely
  Future<void> saveCertificate(String certificate) async {
    try {
      await secureStorage.write(key: certificateKey, value: certificate);
      FhirantLogging().logInfo('Certificate saved securely.');
    } catch (e) {
      FhirantLogging().logError('Error saving certificate: $e');
      rethrow;
    }
  }

  /// Retrieve the private key securely
  Future<String?> getPrivateKey() async {
    try {
      final key = await secureStorage.read(key: privateKeyKey);
      if (key == null) {
        FhirantLogging().logInfo('No private key found in storage.');
      }
      return key;
    } catch (e) {
      FhirantLogging().logError('Error retrieving private key: $e');
      rethrow;
    }
  }

  /// Retrieve the certificate securely
  Future<String?> getCertificate() async {
    try {
      final cert = await secureStorage.read(key: certificateKey);
      if (cert == null) {
        FhirantLogging().logInfo('No certificate found in storage.');
      }
      return cert;
    } catch (e) {
      FhirantLogging().logError('Error retrieving certificate: $e');
      rethrow;
    }
  }

  /// Generate a self-signed certificate
  Future<Map<String, String>> generateSelfSignedCertificate() async {
    try {
      FhirantLogging().logInfo('Generating RSA key pair...');
      final keyPair = CryptoUtils.generateRSAKeyPair();

      FhirantLogging().logInfo('Encoding private key in PEM format...');
      final privateKeyPem = CryptoUtils.encodeRSAPrivateKeyToPem(
        keyPair.privateKey as RSAPrivateKey,
      );

      FhirantLogging().logInfo('Generating CSR...');
      final csr = X509Utils.generateRsaCsrPem(
        {'CN': 'localhost'},
        keyPair.privateKey as RSAPrivateKey,
        keyPair.publicKey as RSAPublicKey,
      );

      FhirantLogging().logInfo('Generating self-signed certificate...');
      final certificatePem = X509Utils.generateSelfSignedCertificate(
        keyPair.privateKey as RSAPrivateKey,
        csr,
        365,
        sans: ['localhost'],
        keyUsage: [KeyUsage.DIGITAL_SIGNATURE, KeyUsage.KEY_ENCIPHERMENT],
        extKeyUsage: [ExtendedKeyUsage.SERVER_AUTH],
      );

      await savePrivateKey(privateKeyPem);
      await saveCertificate(certificatePem);

      FhirantLogging().logInfo(
        'Self-signed certificate generated successfully.',
      );
      return {
        'privateKey': privateKeyPem,
        'certificate': certificatePem,
        'csr': csr,
      };
    } catch (e) {
      FhirantLogging().logError(
        'Error generating self-signed certificate: $e',
      );
      rethrow;
    }
  }

  /// Generates a secure random key of the given [length].
  /// The key will consist of alphanumeric characters.
  static String generateSecureRandomKey(int length) {
    try {
      final secureRandom = CryptoUtils.getSecureRandom();
      const characters =
          'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
      final buffer = StringBuffer();

      for (var i = 0; i < length; i++) {
        buffer.write(characters[secureRandom.nextUint8() % characters.length]);
      }

      return buffer.toString();
    } catch (e) {
      FhirantLogging().logError(
        'Error generating secure random key: $e',
      );
      rethrow;
    }
  }

  /// Generate a secure 256-bit encryption key
  static String generateEncryptionKey() {
    final random = Random.secure();
    final key = List<int>.generate(32, (i) => random.nextInt(256));
    return base64Url.encode(key);
  }
}
