// OWASP ASVS 5.0.0 V15.4.4 (L3, read 2026-10-21): resource allocation
// "prevent[s] thread starvation by ensuring fair access to resources ...
// allowing lower-priority threads to proceed within a reasonable
// timeframe". fhirant serves every request on one isolate. While a large
// transaction Bundle runs, how long can anything else on that isolate wait?
//
// A 10 ms periodic timer on the server's isolate records the gap between
// its ticks from the Bundle's start to its end; the largest gap is the
// longest any other request (or timer) had to wait. Two arms, the way each
// deployment opens its store (a plain file, no cipher, in a temp dir):
//   cli: NativeDatabase(file), SQLite on the server's isolate
//        (bin/server.dart).
//   app: NativeDatabase.createInBackground(file), SQLite on its own isolate
//        (packages/fhirant database_service.dart).
// ASVS gives no number; this reports the one measured.
//
// One row per arm and size to starvation_probe.tsv, flushed as it runs.
//
// Run from packages/fhirant_server:
//   dart run tool/review_2026-10-17/starvation_probe.dart <entries>...
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';

import '../../test/integration/test_helpers.dart';

Future<void> main(List<String> args) async {
  final out = File('tool/review_2026-10-17/starvation_probe.tsv')
      .openSync(mode: FileMode.write)
    ..writeStringSync(
      'arm\tentries\tbundle_ms\tbundle_status\tticks\t'
      'max_gap_ms\tgaps_over_1s\treads_500_ms\tsearch_ms\tsearch_total\n',
    )
    ..flushSync();
  for (final entries in args.map(int.parse)) {
    for (final arm in ['cli', 'app']) {
      final row = await _once(arm, entries);
      out
        ..writeStringSync('$row\n')
        ..flushSync();
      stdout.writeln(row);
    }
  }
  out.closeSync();
}

Future<String> _once(String arm, int entries) async {
  final dir = await Directory.systemTemp.createTemp('fhirant_starve_');
  final file = File('${dir.path}/fhirant.db');
  final db = FhirAntDb(
    arm == 'cli'
        ? NativeDatabase(file)
        : NativeDatabase.createInBackground(file),
  );
  await db.initialize();
  final server = FhirAntServer(db, jwtSecret: testJwtSecret, devMode: true);
  final handler = server.createHandler(server.createRouter());
  const json = {
    'content-type': 'application/fhir+json',
    'accept': 'application/fhir+json',
  };
  final bundle = jsonEncode({
    'resourceType': 'Bundle',
    'type': 'transaction',
    'entry': [
      for (var i = 0; i < entries; i++)
        {
          'resource': {
            'resourceType': 'Observation',
            'status': 'final',
            'code': {'text': 'probe $i'},
          },
          'request': {'method': 'POST', 'url': 'Observation'},
        },
    ],
  });
  final clock = Stopwatch()..start();
  var last = 0;
  var maxGap = 0;
  var over1s = 0;
  var ticks = 0;
  final ticker = Timer.periodic(const Duration(milliseconds: 10), (_) {
    final now = clock.elapsedMilliseconds;
    final gap = now - last;
    if (gap > maxGap) maxGap = gap;
    if (gap > 1000) over1s++;
    last = now;
    ticks++;
  });
  final r =
      await handler(testRequest('POST', '/', body: bundle, headers: json));
  final bundleMs = clock.elapsedMilliseconds;
  ticker.cancel();
  // The stretch after the last tick counts too: with no tick at all, the
  // whole Bundle was one gap.
  final tail = bundleMs - last;
  if (tail > maxGap) maxGap = tail;
  if (tail > 1000) over1s++;
  // The cost side: 500 reads one after another, and one search.
  final created = (jsonDecode(await r.readAsString()) as Map)['entry'] as List;
  final firstId =
      (((created.first as Map)['response'] as Map)['location'] as String)
          .split('/')[1];
  final reads = Stopwatch()..start();
  for (var i = 0; i < 500; i++) {
    await handler(
      testRequest('GET', '/Observation/$firstId', headers: json),
    );
  }
  reads.stop();
  final search = Stopwatch()..start();
  final found = await handler(
    testRequest('GET', '/Observation?status=final&_count=50', headers: json),
  );
  search.stop();
  final total = (jsonDecode(await found.readAsString()) as Map)['total'];
  await db.close();
  await dir.delete(recursive: true);
  return '$arm\t$entries\t$bundleMs\t${r.statusCode}\t$ticks\t$maxGap\t'
      '$over1s\t${reads.elapsedMilliseconds}\t'
      '${search.elapsedMilliseconds}\t$total';
}
