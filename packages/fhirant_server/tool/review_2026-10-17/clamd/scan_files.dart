// Scans each named file through fhirant's ClamdScanner and appends one row
// per file (arm, file, bytes, result) to the TSV it is given, flushed.
//
// Run from packages/fhirant_server, with clamd listening:
//   dart run tool/review_2026-10-17/clamd/scan_files.dart \
//     <port> <out.tsv> <arm> <file>...
import 'dart:io';

import 'package:fhirant_server/src/services/file_scanner.dart';

Future<void> main(List<String> args) async {
  final scanner = ClamdScanner(
    '127.0.0.1',
    port: int.parse(args[0]),
    timeout: const Duration(minutes: 2),
  );
  final out = File(args[1]).openSync(mode: FileMode.append);
  for (final path in args.skip(3)) {
    final bytes = File(path).readAsBytesSync();
    String result;
    try {
      final r = await scanner.scan(bytes);
      result = r is ScanFound ? 'FOUND ${r.signature}' : 'clean';
    } on ScannerUnavailable catch (e) {
      result = 'unavailable: ${e.message}';
    }
    final line =
        '${args[2]}\t${File(path).uri.pathSegments.last}\t${bytes.length}\t'
        '$result';
    out
      ..writeStringSync('$line\n')
      ..flushSync();
    stdout.writeln(line);
  }
  out.closeSync();
}
