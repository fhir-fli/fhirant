import 'package:flutter_test/flutter_test.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';

void main() {
  group('PasswordHasher', () {
    test('hash + verify roundtrip succeeds', () {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hashPassword('MySecureP@ss1', salt);

      expect(PasswordHasher.verifyPassword('MySecureP@ss1', salt, hash), isTrue);
    });

    test('wrong password fails verification', () {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hashPassword('MySecureP@ss1', salt);

      expect(
          PasswordHasher.verifyPassword('WrongPassword', salt, hash), isFalse);
    });
  });
}
