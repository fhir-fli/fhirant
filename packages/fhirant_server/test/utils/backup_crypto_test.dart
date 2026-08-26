import 'dart:convert';

import 'package:fhirant_server/src/utils/backup_crypto.dart';
import 'package:test/test.dart';

void main() {
  const bundle =
      '{"resourceType":"Bundle","type":"collection","entry":[{"resource":'
      '{"resourceType":"Patient","id":"p1","name":[{"family":"Faulkenberry"}]}'
      '}]}';
  const passphrase = 'correct horse battery staple';

  group('round trip', () {
    test('what goes in comes back out', () {
      final envelope = BackupCrypto.encrypt(bundle, passphrase);
      expect(BackupCrypto.decrypt(envelope, passphrase), bundle);
    });

    test('survives non-ASCII content', () {
      const withUnicode =
          '{"resourceType":"Patient","name":[{"family":"Ωmega — ñ 日本"}]}';
      final envelope = BackupCrypto.encrypt(withUnicode, passphrase);
      expect(BackupCrypto.decrypt(envelope, passphrase), withUnicode);
    });

    test('survives an empty bundle', () {
      const empty = '{"resourceType":"Bundle","type":"collection"}';
      final envelope = BackupCrypto.encrypt(empty, passphrase);
      expect(BackupCrypto.decrypt(envelope, passphrase), empty);
    });
  });

  group('the envelope leaks nothing', () {
    test('no patient data appears in the envelope', () {
      final envelope = BackupCrypto.encrypt(bundle, passphrase);
      expect(envelope, isNot(contains('Faulkenberry')));
      expect(envelope, isNot(contains('Patient')));
      expect(envelope, isNot(contains('p1')));
    });

    test('the passphrase does not appear in the envelope', () {
      final envelope = BackupCrypto.encrypt(bundle, passphrase);
      expect(envelope, isNot(contains(passphrase)));
      expect(envelope, isNot(contains('horse')));
    });

    test('it carries no key material — only the parameters to re-derive', () {
      final envelope =
          jsonDecode(BackupCrypto.encrypt(bundle, passphrase)) as Map;
      expect(
        envelope.keys.toSet(),
        {'fhirantBackup', 'kdf', 'cipher', 'ciphertext'},
        reason: 'a field beyond these is a field that might carry the key',
      );
      expect(
        (envelope['kdf'] as Map).keys.toSet(),
        {'alg', 'iterations', 'salt'},
      );
      expect((envelope['cipher'] as Map).keys.toSet(), {'alg', 'iv'});
    });

    test('is self-describing, so a future format is recognised not misread',
        () {
      final envelope =
          jsonDecode(BackupCrypto.encrypt(bundle, passphrase)) as Map;
      expect(envelope['fhirantBackup'], BackupCrypto.formatVersion);
      expect((envelope['kdf'] as Map)['alg'], 'PBKDF2-HMAC-SHA256');
      expect((envelope['cipher'] as Map)['alg'], 'AES-256-GCM');
    });
  });

  group('a wrong passphrase fails loudly', () {
    test('a different passphrase does not decrypt', () {
      final envelope = BackupCrypto.encrypt(bundle, passphrase);
      expect(
        () => BackupCrypto.decrypt(envelope, 'not the passphrase'),
        throwsA(isA<BackupDecryptionException>()),
      );
    });

    test('a one-character difference does not decrypt', () {
      final envelope = BackupCrypto.encrypt(bundle, passphrase);
      expect(
        () => BackupCrypto.decrypt(envelope, '$passphrase '),
        throwsA(isA<BackupDecryptionException>()),
      );
    });

    test('an empty passphrase is refused at encryption', () {
      expect(
        () => BackupCrypto.encrypt(bundle, ''),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('tampering is detected', () {
    test('a flipped ciphertext byte fails the authentication tag', () {
      final envelope =
          jsonDecode(BackupCrypto.encrypt(bundle, passphrase)) as Map;
      final ct = base64.decode(envelope['ciphertext'] as String);
      ct[ct.length ~/ 2] ^= 0x01;
      envelope['ciphertext'] = base64.encode(ct);

      expect(
        () => BackupCrypto.decrypt(jsonEncode(envelope), passphrase),
        throwsA(isA<BackupDecryptionException>()),
        reason: 'GCM must reject an altered file rather than return garbage',
      );
    });

    test('a substituted salt fails', () {
      final envelope =
          jsonDecode(BackupCrypto.encrypt(bundle, passphrase)) as Map;
      (envelope['kdf'] as Map)['salt'] =
          base64Url.encode(List<int>.filled(16, 0));
      expect(
        () => BackupCrypto.decrypt(jsonEncode(envelope), passphrase),
        throwsA(isA<BackupDecryptionException>()),
      );
    });

    test('a lowered iteration count still has to authenticate', () {
      // Downgrading the KDF cost does not help an attacker read the file: the
      // key derived at the lower count is simply the wrong key.
      final envelope =
          jsonDecode(BackupCrypto.encrypt(bundle, passphrase)) as Map;
      (envelope['kdf'] as Map)['iterations'] = 1;
      expect(
        () => BackupCrypto.decrypt(jsonEncode(envelope), passphrase),
        throwsA(isA<BackupDecryptionException>()),
      );
    });

    test('an unknown format version is refused', () {
      final envelope =
          jsonDecode(BackupCrypto.encrypt(bundle, passphrase)) as Map;
      envelope['fhirantBackup'] = 99;
      expect(
        () => BackupCrypto.decrypt(jsonEncode(envelope), passphrase),
        throwsA(isA<BackupDecryptionException>()),
      );
    });

    test('a plain Bundle is not mistaken for an envelope', () {
      expect(
        () => BackupCrypto.decrypt(bundle, passphrase),
        throwsA(isA<BackupDecryptionException>()),
      );
      expect(BackupCrypto.isEnvelope(bundle), isFalse);
      expect(
        BackupCrypto.isEnvelope(BackupCrypto.encrypt(bundle, passphrase)),
        isTrue,
      );
    });
  });

  group('each export stands alone', () {
    test('the same input twice produces different bytes', () {
      final a = BackupCrypto.encrypt(bundle, passphrase);
      final b = BackupCrypto.encrypt(bundle, passphrase);
      expect(a, isNot(equals(b)));
      // Both still decrypt — the difference is fresh salt and nonce, not
      // corruption.
      expect(BackupCrypto.decrypt(a, passphrase), bundle);
      expect(BackupCrypto.decrypt(b, passphrase), bundle);
    });

    test('salt and nonce are fresh per export, never reused', () {
      final envelopes = List.generate(
        20,
        (_) => jsonDecode(BackupCrypto.encrypt(bundle, passphrase)) as Map,
      );
      final salts =
          envelopes.map((e) => (e['kdf'] as Map)['salt'] as String).toSet();
      final ivs =
          envelopes.map((e) => (e['cipher'] as Map)['iv'] as String).toSet();
      expect(salts.length, 20);
      expect(
        ivs.length,
        20,
        reason: 'a repeated nonce under the same key breaks GCM outright',
      );
    });
  });
}
