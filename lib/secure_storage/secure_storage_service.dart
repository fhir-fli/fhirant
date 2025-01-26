import 'package:basic_utils/basic_utils.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure Storage Service
class SecureStorageService {
  /// Encryption key for secure storage
  static const encryptionKey = 'fhirant_encryption_key';

  /// Private key for secure storage
  static const privateKeyKey = 'fhirant_private_key';

  /// Certificate key for secure storage
  static const certificateKey = 'fhirant_certificate_key';

  /// FlutterSecureStorage instance
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();

  /// Save the encryption key securely
  Future<void> saveEncryptionKey(String key) async {
    await secureStorage.write(key: encryptionKey, value: key);
  }

  /// Retrieve the encryption key securely
  Future<String?> getEncryptionKey() async {
    return secureStorage.read(key: encryptionKey);
  }

  /// Generate a random encryption key (for first-time setup)
  String generateRandomKey() {
    return generateSecureRandomKey(256);
  }

  /// Save the private key securely
  Future<void> savePrivateKey(String key) async {
    await secureStorage.write(key: privateKeyKey, value: key);
  }

  /// Save the certificate securely
  Future<void> saveCertificate(String certificate) async {
    await secureStorage.write(key: certificateKey, value: certificate);
  }

  /// Retrieve the private key securely
  Future<String?> getPrivateKey() async {
    return secureStorage.read(key: privateKeyKey);
  }

  /// Retrieve the certificate securely
  Future<String?> getCertificate() async {
    return secureStorage.read(key: certificateKey);
  }

  /// Generate a self-signed certificate
  Future<Map<String, String>> generateSelfSignedCertificate() async {
    // Generate RSA key pair
    final keyPair = CryptoUtils.generateRSAKeyPair();

    // Encode keys in PEM format
    final privateKeyPem = CryptoUtils.encodeRSAPrivateKeyToPem(
      keyPair.privateKey as RSAPrivateKey,
    );

    // Generate CSR (Certificate Signing Request)
    final csr = X509Utils.generateRsaCsrPem(
      {
        'CN': 'localhost', // Set the subject with a Common Name
      },
      keyPair.privateKey as RSAPrivateKey,
      keyPair.publicKey as RSAPublicKey,
    );

    // Generate self-signed certificate
    final certificatePem = X509Utils.generateSelfSignedCertificate(
      keyPair.privateKey as RSAPrivateKey, // RSA private key
      csr, // Certificate Signing Request in PEM format
      365, // Validity in days
      sans: ['localhost'], // Subject Alternative Names
      keyUsage: [
        KeyUsage.DIGITAL_SIGNATURE,
        KeyUsage.KEY_ENCIPHERMENT,
      ], // Define key usage
      extKeyUsage: [
        ExtendedKeyUsage.SERVER_AUTH,
      ], // Define extended key usage
    );

    // Save the keys to secure storage
    await savePrivateKey(privateKeyPem);
    await saveCertificate(certificatePem);

    return {
      'privateKey': privateKeyPem,
      'certificate': certificatePem,
      'csr': csr,
    };
  }

  /// Generates a secure random key of the given [length].
  /// The key will consist of alphanumeric characters.
  static String generateSecureRandomKey(int length) {
    final secureRandom = CryptoUtils.getSecureRandom();
    const characters =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final buffer = StringBuffer();

    for (var i = 0; i < length; i++) {
      buffer.write(characters[secureRandom.nextUint8() % characters.length]);
    }

    return buffer.toString();
  }
}
