// The encrypted-file backup through BackupService on the MIMIC copy: wall
// time and resident memory, appended to <db-dir>/backup_file_bench.tsv.
//   dart run tool/review_2026-09-06/backup_file_bench.dart <db-dir> <out-file>
// ignore_for_file: avoid_print, lines_longer_than_80_chars
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/services/backup_service.dart';

Future<void> main(List<String> args) async {
  final dir = args[0];
  final out = args[1];
  final tsv = File('$dir/backup_file_bench.tsv');
  if (!tsv.existsSync()) tsv.writeAsStringSync('step\tms\trss_mb\tnote\n');
  void row(String step, int ms, [String note = '']) {
    final rss = ProcessInfo.currentRss ~/ (1024 * 1024);
    tsv.writeAsStringSync('$step\t$ms\t$rss\t$note\n', mode: FileMode.append);
    print('$step: ${ms}ms rss=${rss}MB $note');
  }
  if (File(out).existsSync()) File(out).deleteSync();
  final db = FhirAntDb(NativeDatabase(File('$dir/fhirant.sqlite')));
  await db.customSelect('SELECT 1').get();
  row('open', 0);
  final sw = Stopwatch()..start();
  final file = await BackupService.createFile(db, 'correct horse battery staple', out);
  row('createFile', sw.elapsedMilliseconds, '${file.lengthSync()} bytes');
  await db.close();
  final check = Stopwatch()..start();
  final copy = FhirAntDb(
    NativeDatabase(
      File(out),
      setup: (raw) => raw
        ..execute("PRAGMA cipher = '${FhirAntDb.cipherScheme}'")
        ..execute("PRAGMA key = 'correct horse battery staple'"),
    ),
  );
  final n = await copy.customSelect('SELECT count(*) AS c FROM resources').getSingle();
  row('reopen with passphrase', check.elapsedMilliseconds, '${n.read<int>('c')} resources');
  await copy.close();
}
