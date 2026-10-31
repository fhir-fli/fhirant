// What does the Subscription worker cost a write when no Subscription is
// stored? Every create, update and Bundle entry queues its resource, and the
// worker runs one Subscription search per queued change
// (SubscriptionService._evaluate). This times the worker draining 2,000
// changes on a store holding no Subscription, on the CLI's store
// (openStoreFile, under applyStoreCipher), and counts the statements it sends.
//
// One row per run and measure to subscription_worker_probe.tsv, flushed as
// it runs.
//
// Run from packages/fhirant_server:
//   dart run tool/review_2026-10-17/subscription_worker_probe.dart <runs>
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/services/subscription_service.dart';

bool _counting = false;
int _statements = 0;

class _Count extends QueryInterceptor {
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (_counting) _statements++;
    return executor.runSelect(statement, args);
  }
}

Future<void> main(List<String> args) async {
  final runs = int.parse(args.first);
  final out = File('tool/review_2026-10-17/subscription_worker_probe.tsv')
      .openSync(mode: FileMode.write)
    ..writeStringSync('run\tchanges\tdrain_ms\tselects\tus_each\n')
    ..flushSync();
  for (var run = 0; run < runs; run++) {
    final dir = await Directory.systemTemp.createTemp('fhirant_subs_');
    final db = FhirAntDb(
      openStoreFile(File('${dir.path}/fhirant.db'), 'k').interceptWith(
        _Count(),
      ),
    );
    await db.initialize();
    final changes = [
      for (var i = 0; i < 2000; i++)
        fhir.Observation(
          id: fhir.FhirString('o$i'),
          status: fhir.ObservationStatus.final_,
          code: fhir.CodeableConcept(text: fhir.FhirString('probe $i')),
        ),
    ];
    final ok = await db.saveResources(changes);
    if (!ok) throw StateError('saveResources refused the list');
    final subs = SubscriptionService(db);
    _statements = 0;
    _counting = true;
    final clock = Stopwatch()..start();
    for (final c in changes) {
      await subs.onResourceChanged(c);
    }
    await subs.drain();
    clock.stop();
    _counting = false;
    out
      ..writeStringSync(
        '$run\t${changes.length}\t${clock.elapsedMilliseconds}\t$_statements\t'
        '${(clock.elapsedMicroseconds / changes.length).toStringAsFixed(1)}\n',
      )
      ..flushSync();
    await db.close();
    await dir.delete(recursive: true);
  }
  out.closeSync();
}
