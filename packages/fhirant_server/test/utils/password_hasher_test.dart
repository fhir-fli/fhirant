import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';
import 'package:test/test.dart';

/// REVIEW-2026-09-17 A11. A login was 290–337 ms of PBKDF2 on the server
/// isolate, at 120,000 iterations. OWASP Password Storage Cheat Sheet (raw
/// markdown read 2026-09-17), verbatim: "Use Argon2id with a minimum
/// configuration of 19 MiB of memory, an iteration count of 2, and 1
/// degree of parallelism." New hashes are that, computed off the server
/// isolate; the two older formats still verify and are re-hashed on the
/// next login.
void main() {
  group('PasswordHasher', () {
    test('hash + verify roundtrip succeeds', () async {
      final salt = PasswordHasher.generateSalt();
      final hash = await PasswordHasher.hashPassword('MySecureP@ss1', salt);
      expect(
        await PasswordHasher.verifyPassword('MySecureP@ss1', salt, hash),
        isTrue,
      );
    });

    test('wrong password fails verification', () async {
      final salt = PasswordHasher.generateSalt();
      final hash = await PasswordHasher.hashPassword('MySecureP@ss1', salt);
      expect(
        await PasswordHasher.verifyPassword('WrongPassword', salt, hash),
        isFalse,
      );
    });

    test("new hashes are Argon2id at OWASP's minimum, self-describing",
        () async {
      final salt = PasswordHasher.generateSalt();
      final hash = await PasswordHasher.hashPassword('MySecureP@ss1', salt);
      // argon2id$m=<KiB>,t=<iterations>,p=<lanes>$<hex>
      final parts = hash.split(r'$');
      expect(parts, hasLength(3));
      expect(parts[0], 'argon2id');
      expect(parts[1], 'm=19456,t=2,p=1');
      expect(parts[2], hasLength(64));
      final legacyHmac = Hmac(sha256, utf8.encode(salt))
          .convert(utf8.encode('MySecureP@ss1'))
          .toString();
      expect(hash, isNot(contains(legacyHmac)));
    });

    test('the salt changes the derived hash', () async {
      final hashA = await PasswordHasher.hashPassword('same-password', 'a');
      final hashB = await PasswordHasher.hashPassword('same-password', 'b');
      expect(hashA, isNot(hashB));
    });

    test('the hash is computed off the calling isolate', () async {
      // A timer on this isolate fires while the hash runs; it could not if
      // the hash held the isolate for its 100+ ms.
      final sw = Stopwatch()..start();
      final hashing = PasswordHasher.hashPassword('p', 'salt');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final timerFiredAt = sw.elapsedMilliseconds;
      await hashing;
      final hashDoneAt = sw.elapsedMilliseconds;
      expect(timerFiredAt, lessThan(hashDoneAt));
      expect(timerFiredAt, lessThan(50), reason: 'the isolate was held');
    });

    group('older formats still verify (backward compatibility)', () {
      String legacyHmac(String password, String salt) =>
          Hmac(sha256, utf8.encode(salt))
              .convert(utf8.encode(password))
              .toString();

      test('a correct password verifies against a legacy HMAC hash', () async {
        const salt = 'legacy-salt';
        final stored = legacyHmac('OldPassword1!', salt);
        expect(
          await PasswordHasher.verifyPassword('OldPassword1!', salt, stored),
          isTrue,
        );
      });

      test('a wrong password fails against a legacy HMAC hash', () async {
        const salt = 'legacy-salt';
        final stored = legacyHmac('OldPassword1!', salt);
        expect(
          await PasswordHasher.verifyPassword('nope', salt, stored),
          isFalse,
        );
      });

      test('a PBKDF2 hash written by the previous hasher verifies', () async {
        // pbkdf2$1000$<hex>: PBKDF2-HMAC-SHA256('p', 'salt', 1000, 32),
        // computed independently with package:crypto below, so the
        // expectation is the algorithm's and not this class's.
        final salt = utf8.encode('salt');
        final pw = utf8.encode('p');
        final hmac = Hmac(sha256, pw);
        var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
        final t = List<int>.from(u);
        for (var i = 1; i < 1000; i++) {
          u = hmac.convert(u).bytes;
          for (var j = 0; j < t.length; j++) {
            t[j] ^= u[j];
          }
        }
        final hex = t.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        final stored = 'pbkdf2\$1000\$$hex';
        expect(
          await PasswordHasher.verifyPassword('p', 'salt', stored),
          isTrue,
        );
        expect(
          await PasswordHasher.verifyPassword('q', 'salt', stored),
          isFalse,
        );
      });
    });

    group('needsRehash', () {
      test('flags a legacy HMAC hash', () {
        final legacy =
            Hmac(sha256, utf8.encode('s')).convert(utf8.encode('p')).toString();
        expect(PasswordHasher.needsRehash(legacy), isTrue);
      });

      test('flags a PBKDF2 hash, at any iteration count', () {
        expect(PasswordHasher.needsRehash(r'pbkdf2$120000$abcd'), isTrue);
        expect(PasswordHasher.needsRehash(r'pbkdf2$600000$abcd'), isTrue);
      });

      test('flags Argon2id below the current parameters', () {
        expect(
          PasswordHasher.needsRehash(r'argon2id$m=7168,t=5,p=1$ab'),
          isTrue,
        );
      });

      test('does not flag a current hash', () async {
        final hash = await PasswordHasher.hashPassword(
          'p',
          PasswordHasher.generateSalt(),
        );
        expect(PasswordHasher.needsRehash(hash), isFalse);
      });
    });
  });
}
