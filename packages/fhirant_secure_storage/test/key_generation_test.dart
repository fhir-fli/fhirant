import 'dart:convert';

import 'package:fhirant_secure_storage/fhirant_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// These generators produce the key that encrypts the patient database and the
/// material behind the server's TLS identity. The package shipped with no
/// tests at all; this is the part that most needed them.
void main() {
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  group('generateSecureRandomKey', () {
    test('returns the requested length', () {
      expect(SecureStorageService.generateSecureRandomKey(32).length, 32);
      expect(SecureStorageService.generateSecureRandomKey(1).length, 1);
    });

    test('uses only the documented alphabet', () {
      final key = SecureStorageService.generateSecureRandomKey(2048);
      expect(
        key.split('').every(alphabet.contains),
        isTrue,
        reason: 'a character outside the alphabet means the index arithmetic '
            'is wrong, not that the key is stronger',
      );
    });

    test('does not repeat itself between calls', () {
      final keys = List.generate(
        50,
        (_) => SecureStorageService.generateSecureRandomKey(32),
      ).toSet();
      expect(keys.length, 50);
    });

    test('does not favour the front of the alphabet', () {
      // Regression guard. This drew a byte 0-255 and took it modulo 62; 256 is
      // not a multiple of 62, so 'A'-'H' came from five byte values each and
      // the rest from four — about 25% more often. Rejection sampling fixed
      // it, and this is the test that fails if the modulo comes back.
      const draws = 120000;
      final counts = <String, int>{for (final c in alphabet.split('')) c: 0};
      final key = SecureStorageService.generateSecureRandomKey(draws);
      for (final c in key.split('')) {
        counts[c] = counts[c]! + 1;
      }

      const expected = draws / alphabet.length;
      final biased = alphabet.substring(0, 8).split('');
      final rest = alphabet.substring(8).split('');
      final biasedMean =
          biased.map((c) => counts[c]!).reduce((a, b) => a + b) / biased.length;
      final restMean =
          rest.map((c) => counts[c]!).reduce((a, b) => a + b) / rest.length;

      // The old bug put this ratio at ~1.25. Sampling noise at this many
      // draws is well under a percent, so 1.05 separates the two cleanly
      // without being flaky.
      expect(
        biasedMean / restMean,
        lessThan(1.05),
        reason: 'the first eight characters are over-represented — the modulo '
            'bias is back',
      );

      // And nothing else drifted far from uniform either.
      for (final c in alphabet.split('')) {
        expect((counts[c]! - expected).abs() / expected, lessThan(0.15));
      }
    });
  });

  group('generateEncryptionKey', () {
    test('is 32 bytes of base64url, i.e. a 256-bit key', () {
      final key = SecureStorageService.generateEncryptionKey();
      expect(base64Url.decode(key).length, 32);
    });

    test('does not repeat itself between calls', () {
      final keys =
          List.generate(50, (_) => SecureStorageService.generateEncryptionKey())
              .toSet();
      expect(keys.length, 50);
    });

    test('is not derived from the clock', () {
      // The database key used to be microsecondsSinceEpoch + an identity hash
      // code, so two keys made in quick succession shared a long prefix and
      // the whole thing was guessable from roughly when the app was first
      // run. Keys minted back to back must share no meaningful prefix.
      final a = SecureStorageService.generateEncryptionKey();
      final b = SecureStorageService.generateEncryptionKey();
      var shared = 0;
      while (shared < a.length && shared < b.length && a[shared] == b[shared]) {
        shared++;
      }
      expect(shared, lessThan(4));
    });
  });
}
