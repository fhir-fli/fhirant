import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';
import 'package:test/test.dart';

void main() {
  group('PasswordHasher', () {
    test('hash + verify roundtrip succeeds', () {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hashPassword('MySecureP@ss1', salt);

      expect(
        PasswordHasher.verifyPassword('MySecureP@ss1', salt, hash),
        isTrue,
      );
    });

    test('wrong password fails verification', () {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hashPassword('MySecureP@ss1', salt);

      expect(
        PasswordHasher.verifyPassword('WrongPassword', salt, hash),
        isFalse,
      );
    });

    test('new hashes are PBKDF2 (slow KDF), not a bare HMAC digest', () {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hashPassword('MySecureP@ss1', salt);

      // Self-describing format: pbkdf2$<iterations>$<hexDigest>.
      final parts = hash.split(r'$');
      expect(parts, hasLength(3));
      expect(parts[0], 'pbkdf2');
      expect(int.parse(parts[1]), PasswordHasher.pbkdf2Iterations);
      // The stored value is NOT the single-round HMAC (the old format).
      final legacyHmac = Hmac(sha256, utf8.encode(salt))
          .convert(utf8.encode('MySecureP@ss1'))
          .toString();
      expect(hash, isNot(contains(legacyHmac)));
    });

    test('the salt changes the derived hash', () {
      final hashA = PasswordHasher.hashPassword('same-password', 'salt-a');
      final hashB = PasswordHasher.hashPassword('same-password', 'salt-b');
      expect(hashA, isNot(hashB));
    });

    group('legacy HMAC-SHA256 hashes still verify (backward compatibility)',
        () {
      // Reproduces exactly how the old PasswordHasher stored hashes.
      String legacyHash(String password, String salt) =>
          Hmac(sha256, utf8.encode(salt))
              .convert(utf8.encode(password))
              .toString();

      test('a correct password verifies against a legacy hash', () {
        const salt = 'legacy-salt';
        final stored = legacyHash('OldPassword1!', salt);
        expect(
          PasswordHasher.verifyPassword('OldPassword1!', salt, stored),
          isTrue,
        );
      });

      test('a wrong password fails against a legacy hash', () {
        const salt = 'legacy-salt';
        final stored = legacyHash('OldPassword1!', salt);
        expect(
          PasswordHasher.verifyPassword('nope', salt, stored),
          isFalse,
        );
      });
    });

    group('needsRehash', () {
      test('flags a legacy HMAC hash for upgrade', () {
        final legacy =
            Hmac(sha256, utf8.encode('s')).convert(utf8.encode('p')).toString();
        expect(PasswordHasher.needsRehash(legacy), isTrue);
      });

      test('does not flag a current PBKDF2 hash', () {
        final hash =
            PasswordHasher.hashPassword('p', PasswordHasher.generateSalt());
        expect(PasswordHasher.needsRehash(hash), isFalse);
      });

      test('flags a PBKDF2 hash with too few iterations', () {
        expect(PasswordHasher.needsRehash(r'pbkdf2$1000$abcd'), isTrue);
      });
    });
  });
}
