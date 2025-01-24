import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// SecureStorageService
class SecureStorageService {
  static const _encryptionKey = 'fhirant_encryption_key';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  /// Save the encryption key securely
  Future<void> saveEncryptionKey(String key) async {
    await _secureStorage.write(key: _encryptionKey, value: key);
  }

  /// Retrieve the encryption key securely
  Future<String?> getEncryptionKey() async {
    return _secureStorage.read(key: _encryptionKey);
  }

  /// Generate a random key (for first-time setup)
  String generateRandomKey() {
    return List.generate(32, (index) => String.fromCharCode(65 + index)).join();
  }
}
