// A PEM certificate and a 95-character SHA-256 fingerprint cannot be wrapped
// without changing what they are.
// ignore_for_file: lines_longer_than_80_chars

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

  group('certificateFingerprint', () {
    // A real self-signed certificate, and the fingerprint OpenSSL reports for
    // it: `openssl x509 -noout -fingerprint -sha256`. Hard-coded rather than
    // recomputed in the test, because recomputing it the way the
    // implementation does would only prove the code agrees with itself.
    // Pinning is worth nothing unless both ends compute the same number as
    // every other tool.
    const pem =
        '-----BEGIN CERTIFICATE-----\nMIIDCTCCAfGgAwIBAgIUQUlreJbB7M1UPvjuxbMP/CsBscowDQYJKoZIhvcNAQEL\nBQAwFDESMBAGA1UEAwwJbG9jYWxob3N0MB4XDTI2MDgyNjAwMzYzMVoXDTI2MDgy\nNzAwMzYzMVowFDESMBAGA1UEAwwJbG9jYWxob3N0MIIBIjANBgkqhkiG9w0BAQEF\nAAOCAQ8AMIIBCgKCAQEAuZUJGhf6KsqIEVrMMgb+iv+gT9Ss80TVv/vdcwTdpg9f\n9NTSR+suL6S9oAD59+be+EmFqvbBJhSEQDulyeWyyG3vcwX1fhNLKQB6BJRwYPvU\nXpLvsY1Bjeeyq5BG4GioUvM1nzKMY19u4cQmmLKLnrd0EhJkUX2Q/VJ5HkaU0nf4\nXXSU6MPDMZ57AtBUHz1PLeT2YRfX5oHJbFQ9rPORz3dZy9SXZ5Mff1qAFW6vsWLn\ngxNyk4UXYZFzG4kTG3DzRsLlFrq3nXKOxv8T2UqJobfubV4rF+zFRiZDH3P/9OCW\nPriRjWANlonQeyEM26JNcbSZ2wO7H0LKku7nRuZjyQIDAQABo1MwUTAdBgNVHQ4E\nFgQUYwGON4BscaVMqpFe7aUCOsCaoUAwHwYDVR0jBBgwFoAUYwGON4BscaVMqpFe\n7aUCOsCaoUAwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAnquZ\n/glQPK1YPpv+oHyD2R31ZW9D5KTcnXGE6/RrCHZDHYa5Dx4DxiC7dcXTduIR/xXS\nFR75J1wtWg4v2j+pHMo41PmHV7kwoQ19luU07WYcTLPkTFT20cUjKmdz1SpPl2IX\ny2inH/TYeLaYEnUnZELCYmR/gVXx5brgkdvZoZvr8Mc5rYVCj4HYt+E8I2sIYBUG\nakuhHbPwAbBll1Xud0ymGh062wgI/WcoY8UUqynYzzrP/ZGMopP5aCKn7BYCtMLp\n9asIeACChQu/3M6pet7h/pW1asG9l1FgG9eaRmYW/6yIknBbhm4T/Y06TC+21Gej\nfVrxD1RAWd5RVv4cyQ==\n-----END CERTIFICATE-----';

    const opensslFingerprint =
        '6f:c9:83:04:68:e4:90:40:01:2e:1b:bf:69:c8:53:a6:84:4a:95:6d:4a:dc:f5:1d:85:85:ae:3a:0f:d4:e4:ca';

    test('matches what OpenSSL reports for the same certificate', () {
      final computed = SecureStorageService.certificateFingerprint(pem);
      expect(computed, opensslFingerprint);
    });

    test('is lowercase hex, colon separated, 32 bytes', () {
      final parts = SecureStorageService.certificateFingerprint(pem).split(':');
      expect(parts.length, 32);
      expect(parts.every((p) => p.length == 2), isTrue);
    });

    test('is insensitive to PEM line endings', () {
      // A device paired before the PEM was rewrapped must still connect after.
      final rewrapped = pem.replaceAll('\n', '\r\n');
      final computed = SecureStorageService.certificateFingerprint(rewrapped);
      expect(computed, opensslFingerprint);
    });

    test('a different certificate gives a different fingerprint', () {
      final altered = pem.replaceFirst('MII', 'MIJ');
      expect(
        SecureStorageService.certificateFingerprint(altered),
        isNot(opensslFingerprint),
      );
    });
  });
}
