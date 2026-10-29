// Two measurements behind bundle_statements_probe.dart's reading, on each
// way of opening the store (both under applyStoreCipher):
//   trip:  10,000 `SELECT 1`, one after another, so the time per trip to
//          the store is timed, not derived from totals.
//   one:   2,000 Observations saved one saveResource at a time inside one
//          transaction, as the Bundle handler does.
//   list:  the same 2,000 through saveResources, one call.
//
// One row per arm, run and measure to round_trip_probe.tsv, flushed as it
// runs.
//
// Run from packages/fhirant_server:
//   dart run tool/review_2026-10-17/round_trip_probe.dart <runs>
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';

List<fhir.Observation> _observations(String prefix) => [
      for (var i = 0; i < 2000; i++)
        fhir.Observation(
          id: fhir.FhirString('$prefix$i'),
          status: fhir.ObservationStatus.final_,
          code: fhir.CodeableConcept(text: fhir.FhirString('probe $i')),
        ),
    ];

Future<void> main(List<String> args) async {
  final runs = int.parse(args.first);
  final out = File('tool/review_2026-10-17/round_trip_probe.tsv')
      .openSync(mode: FileMode.write)
    ..writeStringSync('arm\trun\tmeasure\tcount\tms\tus_each\n')
    ..flushSync();
  void row(String arm, int run, String measure, int count, int us) {
    out
      ..writeStringSync(
        '$arm\t$run\t$measure\t$count\t${us ~/ 1000}\t'
        '${(us / count).toStringAsFixed(1)}\n',
      )
      ..flushSync();
  }

  for (var run = 0; run < runs; run++) {
    for (final arm in ['same-isolate', 'background']) {
      final dir = await Directory.systemTemp.createTemp('fhirant_trip_');
      final file = File('${dir.path}/fhirant.db');
      final db = FhirAntDb(
        arm == 'same-isolate'
            ? NativeDatabase(file, setup: (raw) => applyStoreCipher(raw, 'k'))
            : openStoreFile(file, 'k'),
      );
      await db.initialize();

      var clock = Stopwatch()..start();
      for (var i = 0; i < 10000; i++) {
        await db.customSelect('SELECT 1').get();
      }
      row(arm, run, 'trip', 10000, clock.elapsedMicroseconds);

      clock = Stopwatch()..start();
      await db.transaction(() async {
        for (final o in _observations('one')) {
          await db.saveResource(o);
        }
      });
      row(arm, run, 'one', 2000, clock.elapsedMicroseconds);

      clock = Stopwatch()..start();
      final ok = await db.saveResources(_observations('list'));
      if (!ok) throw StateError('saveResources refused the list');
      row(arm, run, 'list', 2000, clock.elapsedMicroseconds);

      await db.close();
      await dir.delete(recursive: true);
    }
  }
  out.closeSync();
}
