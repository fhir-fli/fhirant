// The part of a scanned `$restore` that the scan adds, timed alone: every
// row of an encrypted backup's `resources` table parsed and passed to
// fileRefusal with a scanner, as BackupService.restoreFile's admit check
// does, without the merge. restore_scan_cost.tsv times whole restores,
// whose run-to-run spread is wider than this step.
//
// Writes <store-dir>'s backup once (BackupService.createFile), then one row
// per run to restore_screen_cost.tsv, flushed as it is written.
//
// Run from packages/fhirant_server:
//   dart run tool/review_2026-10-17/restore_screen_cost.dart <store-dir> <runs>
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/services/backup_service.dart';
import 'package:fhirant_server/src/services/file_scanner.dart';
import 'package:fhirant_server/src/utils/file_refusal.dart';

import '../../test/services/fake_clamd.dart';

const _passphrase = 'restore screen cost';

Future<void> main(List<String> args) async {
  final store = args[0];
  final runs = int.parse(args[1]);
  final out = File('tool/review_2026-10-17/restore_screen_cost.tsv')
      .openSync(mode: FileMode.write)
    ..writeStringSync('run\trows\tms\tus_per_row\trefused\tfiles_scanned\n')
    ..flushSync();

  final scratch = await Directory.systemTemp.createTemp('fhirant_screen_');
  final path = '${scratch.path}/backup.sqlite';
  final source = FhirAntDb(NativeDatabase(File('$store/fhirant.sqlite')));
  await source.initialize();
  await BackupService.createFile(source, _passphrase, path);
  await source.close();

  final backup = FhirAntDb(
    NativeDatabase(
      File(path),
      setup: (raw) => applyStoreCipher(raw, _passphrase),
    ),
  );
  final clamd = await FakeClamd.start();
  final scanner = ClamdScanner(
    '127.0.0.1',
    port: clamd.port,
    timeout: const Duration(seconds: 30),
  );
  for (var run = 0; run < runs; run++) {
    final before = clamd.streams.length;
    var rows = 0;
    var refused = 0;
    var after = 0;
    final clock = Stopwatch()..start();
    while (true) {
      // The same page and order as FhirAntDb's screen of a backup.
      final page = await backup.customSelect(
        'SELECT rowid AS r, resource FROM resources WHERE rowid > ? '
        'ORDER BY rowid LIMIT 500',
        variables: [Variable.withInt(after)],
      ).get();
      if (page.isEmpty) break;
      for (final row in page) {
        after = row.read<int>('r');
        rows++;
        final resource =
            fhir.Resource.fromJsonString(row.read<String>('resource'));
        if (await fileRefusal(scanner, resource) != null) refused++;
      }
    }
    final ms = clock.elapsedMilliseconds;
    out
      ..writeStringSync(
        '$run\t$rows\t$ms\t${(ms * 1000 / rows).toStringAsFixed(1)}\t'
        '$refused\t${clamd.streams.length - before}\n',
      )
      ..flushSync();
    stdout.writeln('run $run: $rows rows in $ms ms');
  }
  await clamd.close();
  await backup.close();
  await scratch.delete(recursive: true);
  out.closeSync();
}
