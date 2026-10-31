// What scanning a `$restore` costs on a large encrypted backup. Every row
// of the backup that holds a resource is now parsed so its files can be
// found and scanned (BackupService.restoreFile, OWASP ASVS 5.0.0 V5.4.3);
// before, the rows were copied by SQL unread.
//
// Backs up the store at <store-dir>/fhirant.sqlite (tool/perf_load.dart's
// layout) once with BackupService.createFile, then restores a fresh copy of
// that file into an empty file store, by arm and run:
//   none:    no scanner (as before the change)
//   scanner: a ClamdScanner on test/services/fake_clamd.dart
// The arms alternate in order from run to run.
//
// One row per backup and per restore to restore_scan_cost.tsv, flushed as
// it is written.
//
// Run from packages/fhirant_server:
//   dart run tool/review_2026-10-17/restore_scan_cost.dart <store-dir> <runs>
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/services/backup_service.dart';
import 'package:fhirant_server/src/services/file_scanner.dart';

import '../../test/services/fake_clamd.dart';

const _passphrase = 'restore scan cost';

Future<void> main(List<String> args) async {
  final store = args[0];
  final runs = int.parse(args[1]);
  final out = File('tool/review_2026-10-17/restore_scan_cost.tsv')
      .openSync(mode: FileMode.write)
    ..writeStringSync(
      'step\tarm\trun\tms\tbackup_bytes\tresources\tsaved\tleft_out\t'
      'files_scanned\n',
    )
    ..flushSync();
  void row(List<Object> values) => out
    ..writeStringSync('${values.join('\t')}\n')
    ..flushSync();

  final scratch = await Directory.systemTemp.createTemp('fhirant_scan_cost_');
  final backup = '${scratch.path}/backup.sqlite';
  final source = FhirAntDb(NativeDatabase(File('$store/fhirant.sqlite')));
  await source.initialize();
  final resources = (await source
          .customSelect('SELECT count(*) AS c FROM resources')
          .getSingle())
      .read<int>('c');
  var clock = Stopwatch()..start();
  await BackupService.createFile(source, _passphrase, backup);
  final bytes = File(backup).lengthSync();
  row([
    'backup',
    '-',
    0,
    clock.elapsedMilliseconds,
    bytes,
    resources,
    '',
    '',
    '',
  ]);
  await source.close();

  final clamd = await FakeClamd.start();
  for (var run = 0; run < runs; run++) {
    final arms = run.isEven ? ['none', 'scanner'] : ['scanner', 'none'];
    for (final arm in arms) {
      final copy = await File(backup).copy('${scratch.path}/upload');
      final target = FhirAntDb(
        NativeDatabase(
          File('${scratch.path}/target.sqlite'),
          setup: (raw) => applyStoreCipher(raw, 'k'),
        ),
      );
      await target.initialize();
      final before = clamd.streams.length;
      clock = Stopwatch()..start();
      final result = await BackupService.restoreFile(
        target,
        copy.path,
        passphrase: _passphrase,
        scanner: arm == 'none'
            ? null
            : ClamdScanner(
                '127.0.0.1',
                port: clamd.port,
                timeout: const Duration(seconds: 30),
              ),
      );
      row([
        'restore',
        arm,
        run,
        clock.elapsedMilliseconds,
        bytes,
        resources,
        result.saved,
        result.failed,
        clamd.streams.length - before,
      ]);
      stdout.writeln('$arm $run ${clock.elapsedMilliseconds} ms');
      await target.close();
      for (final f in scratch.listSync()) {
        if (f.path != backup) f.deleteSync();
      }
    }
  }
  await clamd.close();
  await scratch.delete(recursive: true);
  out.closeSync();
}
