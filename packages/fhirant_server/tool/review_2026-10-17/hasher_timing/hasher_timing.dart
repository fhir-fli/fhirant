// What password_hasher_test's "the hash is computed off the calling
// isolate" measures, and how wide its margins are. That test failed once in
// a full run on 2026-10-21 (timer at 61 ms against its 50 ms bound, load
// average 22.6 on 16 cores) and passed 3 of 3 alone.
//
// Two arms, the test's own sequence each time: start the hash, wait 5 ms on
// a timer, note when the timer fired, await the hash, note when it ended.
//   isolate: PasswordHasher.hashPassword, as shipped (Isolate.run).
//   held:    PasswordHasher.hashPasswordSync on the calling isolate, the
//            regression the test exists to catch.
// One row per run to hasher_timing_<label>.tsv, written and flushed as it
// runs.
//
// Run from packages/fhirant_server:
//   dart run tool/review_2026-10-17/hasher_timing/hasher_timing.dart <runs> <label>
import 'dart:io';

import 'package:fhirant_server/src/utils/password_hasher.dart';

Future<void> main(List<String> args) async {
  final runs = int.parse(args[0]);
  final label = args[1];
  final out = File('tool/review_2026-10-17/hasher_timing/'
          'hasher_timing_$label.tsv')
      .openSync(mode: FileMode.write)
    ..writeStringSync('arm\trun\ttimer_fired_ms\thash_done_ms\n')
    ..flushSync();
  for (var i = 0; i < runs; i++) {
    for (final arm in ['isolate', 'held']) {
      final sw = Stopwatch()..start();
      final hashing = arm == 'isolate'
          ? PasswordHasher.hashPassword('p', 'salt')
          : Future.value(PasswordHasher.hashPasswordSync('p', 'salt'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final timerFiredAt = sw.elapsedMicroseconds / 1000;
      await hashing;
      final hashDoneAt = sw.elapsedMicroseconds / 1000;
      out
        ..writeStringSync('$arm\t$i\t$timerFiredAt\t$hashDoneAt\n')
        ..flushSync();
    }
  }
  out.closeSync();
}
