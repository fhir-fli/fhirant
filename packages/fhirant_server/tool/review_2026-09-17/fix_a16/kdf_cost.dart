// Measures the passphrase key derivation of the backup envelope at the
// iteration counts the ceiling decision needs. Writes one row per
// measurement to kdf_cost.tsv as it goes.
//
//   cd packages/fhirant_server && dart run tool/review_2026-09-17/fix_a16/kdf_cost.dart
import 'dart:io';

import 'package:fhirant_server/src/utils/backup_crypto.dart';

void main() {
  final out = File('tool/review_2026-09-17/fix_a16/kdf_cost.tsv')
      .openSync(mode: FileMode.write)
    ..writeStringSync('iterations\trun\tms\n')
    ..flushSync();
  for (final iterations in [
    BackupCrypto.kdfIterations,
    BackupCrypto.kdfIterations * 10,
  ]) {
    for (var run = 1; run <= 3; run++) {
      final sw = Stopwatch()..start();
      // ignore: invalid_use_of_visible_for_testing_member
      BackupCrypto.deriveKeyForMeasurement('passphrase', iterations);
      sw.stop();
      out
        ..writeStringSync('$iterations\t$run\t${sw.elapsedMilliseconds}\n')
        ..flushSync();
      stdout.writeln('$iterations\t$run\t${sw.elapsedMilliseconds} ms');
    }
  }
  out.closeSync();
}
