// Against a real clamd (clamav/clamav:1.5.4 with fhirant's clamav/clamd.conf),
// through fhirant's own ClamdScanner:
//   - the EICAR test file must be a match (the known positive);
//   - a zip holding EICAR must be a match (clamd reads the zip);
//   - zips whose one member expands past MaxFileSize (150 MiB) or
//     MaxScanSize (450 MiB): expected to be a match under AlertExceedsMax.
//     Measured 2026-10-21: both clean. libclamav/unzip.c (1.5.4) trims a
//     member at MaxFileSize without an alert;
//   - how long a scan takes, by size, up to the largest file a 16 MiB
//     request body can carry (base64 is 4 bytes per 3, so 12 MiB).
// The timings set the CLI's default scan deadline.
//
// One row per scan to scan_timing.tsv, flushed as it runs.
//
// Run from packages/fhirant_server, with clamd listening:
//   dart run tool/review_2026-10-17/clamd/scan_timing.dart <port> <zip>...
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:fhirant_server/src/services/file_scanner.dart';

const _eicar =
    r'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*';

Future<void> main(List<String> args) async {
  final scanner = ClamdScanner(
    '127.0.0.1',
    port: int.parse(args[0]),
    timeout: const Duration(minutes: 2),
  );
  final out = File('tool/review_2026-10-17/clamd/scan_timing.tsv')
      .openSync(mode: FileMode.write)
    ..writeStringSync('case\tbytes\trun\tms\tresult\n')
    ..flushSync();
  Future<void> row(String name, Uint8List bytes, int run) async {
    final clock = Stopwatch()..start();
    String result;
    try {
      final r = await scanner.scan(bytes);
      result = r is ScanFound ? 'FOUND ${r.signature}' : 'clean';
    } on ScannerUnavailable catch (e) {
      result = 'unavailable: ${e.message}';
    }
    final line = '$name\t${bytes.length}\t$run\t'
        '${clock.elapsedMilliseconds}\t$result';
    out
      ..writeStringSync('$line\n')
      ..flushSync();
    stdout.writeln(line);
  }

  await row('eicar', Uint8List.fromList(latin1.encode(_eicar)), 1);
  for (final zip in args.skip(1)) {
    await row(File(zip).uri.pathSegments.last, File(zip).readAsBytesSync(), 1);
  }
  final random = Random(1);
  for (final size in [0, 1024, 1024 * 1024, 12 * 1024 * 1024]) {
    final bytes = Uint8List.fromList(
      List<int>.generate(size, (_) => random.nextInt(256)),
    );
    for (var run = 1; run <= 5; run++) {
      await row('random', bytes, run);
    }
  }
  out.closeSync();
}
