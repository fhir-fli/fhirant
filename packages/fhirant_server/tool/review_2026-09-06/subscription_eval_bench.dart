// What one write costs the subscription worker, by the number of active
// subscriptions: the Subscription search plus one `_id` search per
// subscription of the changed type (REVIEW-2026-09-06 row 37's "NOT done:
// caching the active subscriptions"; measured here before deciding).
//
//   dart run tool/review_2026-09-06/subscription_eval_bench.dart \
//     tool/review_2026-09-06/subscription_eval_bench.tsv <label> [0,1,10,100]
//
// Every row is appended and flushed as it is measured. Channel: websocket,
// whose delivery is an in-memory ping, so the numbers are evaluation only.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/services/subscription_service.dart';

Future<void> main(List<String> args) async {
  final tsv = File(args[0]);
  final label = args[1];
  final counts = (args.length > 2 ? args[2] : '0,1,10,100')
      .split(',')
      .map(int.parse)
      .toList();
  const observations = 5000;
  const writes = 30;
  if (!tsv.existsSync()) {
    tsv.writeAsStringSync(
      'label\tsubscriptions\tobservations\twrites\teval_p50_ms\teval_mean_ms'
      '\teval_max_ms\tsub_search_ms\tone_match_ms\n',
    );
  }

  fhir.Observation observation(int i, {String status = 'final'}) =>
      fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': 'o$i',
        'status': status,
        'code': {
          'coding': [
            {
              'system': 'http://loinc.org',
              'code': i.isEven ? '8480-6' : '8462-4',
            },
          ],
        },
        'subject': {'reference': 'Patient/p${i % 500}'},
        'effectiveDateTime':
            '2024-01-${(i % 28 + 1).toString().padLeft(2, '0')}',
        'valueQuantity': {'value': 100 + i % 60, 'code': 'mm[Hg]'},
      });

  for (final subscriptions in counts) {
    final db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
    for (var start = 0; start < observations; start += 500) {
      await db.saveResources([
        for (var i = start; i < start + 500; i++) observation(i),
      ]);
    }
    // Criteria in rotation: all match, half match, other type.
    const criteria = [
      'Observation?status=final',
      'Observation?code=http://loinc.org|8480-6',
      'Patient?active=true',
    ];
    for (var s = 0; s < subscriptions; s++) {
      await db.saveResource(
        fhir.Subscription.fromJson({
          'resourceType': 'Subscription',
          'id': 's$s',
          'status': 'active',
          'reason': 'bench',
          'criteria': criteria[s % criteria.length],
          'channel': {'type': 'websocket'},
        }),
      );
    }
    final service = SubscriptionService(db);

    // The two parts on their own.
    final swSub = Stopwatch()..start();
    final stored = await db.search(
      resourceType: fhir.R4ResourceType.Subscription,
      searchParameters: {
        'status': ['active,error'],
      },
    );
    swSub.stop();
    final probe = observation(0);
    var oneMatchMs = 0.0;
    if (stored.isNotEmpty) {
      final swMatch = Stopwatch()..start();
      await service.matches(stored.first as fhir.Subscription, probe);
      swMatch.stop();
      oneMatchMs = swMatch.elapsedMicroseconds / 1000;
    }

    // Whole evaluations, one per write, worker drained each time.
    final samples = <double>[];
    for (var w = 0; w < writes; w++) {
      final changed = (await db.saveResource(observation(observations + w)))!;
      final sw = Stopwatch()..start();
      await service.onResourceChanged(changed);
      await service.drain();
      sw.stop();
      samples.add(sw.elapsedMicroseconds / 1000);
    }
    samples.sort();
    final p50 = samples[samples.length ~/ 2];
    final mean = samples.reduce((a, b) => a + b) / samples.length;
    final row = '$label\t$subscriptions\t$observations\t$writes\t'
        '${p50.toStringAsFixed(2)}\t${mean.toStringAsFixed(2)}\t'
        '${samples.last.toStringAsFixed(2)}\t'
        '${(swSub.elapsedMicroseconds / 1000).toStringAsFixed(2)}\t'
        '${oneMatchMs.toStringAsFixed(2)}\n';
    tsv.writeAsStringSync(row, mode: FileMode.append, flush: true);
    stdout.write(row);
    await stdout.flush();
    await db.close();
  }
}
