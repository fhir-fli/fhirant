// Review 2026-09-06: what the pure-Dart PBKDF2 and AES-GCM cost. Run from
// packages/fhirant_server: dart run tool/review_2026-09-06/kdf_bench.dart
// ignore_for_file: lines_longer_than_80_chars, require_trailing_commas
import 'dart:io';

import 'package:fhirant_server/src/utils/backup_crypto.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';

void main() {
  final out = File('tool/review_2026-09-06/kdf_bench.tsv')
    ..writeAsStringSync('what\tms\n');
  // Appended synchronously per row, so a killed run keeps what it measured.
  void rowOut(String what, int ms) =>
      out.writeAsStringSync('$what\t$ms\n', mode: FileMode.append);
  final salt = PasswordHasher.generateSalt();
  for (var i = 0; i < 3; i++) {
    final sw = Stopwatch()..start();
    PasswordHasher.hashPassword('correct horse battery staple', salt);
    sw.stop();
    rowOut('pbkdf2_120000_login', sw.elapsedMilliseconds);
    stdout.writeln('login hash: ${sw.elapsedMilliseconds} ms');
  }
  for (var i = 0; i < 2; i++) {
    final sw = Stopwatch()..start();
    BackupCrypto.encrypt('x' * 1000, 'passphrase-passphrase');
    sw.stop();
    rowOut('pbkdf2_210000_backup_1kb', sw.elapsedMilliseconds);
    stdout.writeln('backup kdf+encrypt 1 KB: ${sw.elapsedMilliseconds} ms');
  }
  final big = 'y' * (50 * 1024 * 1024);
  final sw = Stopwatch()..start();
  final env = BackupCrypto.encrypt(big, 'passphrase-passphrase');
  sw.stop();
  rowOut('backup_encrypt_50MB', sw.elapsedMilliseconds);
  stdout.writeln(
      'backup encrypt 50 MB: ${sw.elapsedMilliseconds} ms, envelope ${env.length ~/ (1024 * 1024)} MB, rss ${ProcessInfo.currentRss ~/ (1024 * 1024)} MB');
}
