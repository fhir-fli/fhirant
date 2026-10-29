// OWASP ASVS 5.0.0 V15.4.4 against a running CLI server: while a 2,000-
// entry transaction Bundle runs, how long does a request wait?
// starvation_probe.dart measures the store in process; this measures the
// binary as deployed (bin/server.dart), before and after it opened its
// store with openStoreFile.
//
// <path> is polled one request at a time, 50 ms apart, so a 2-3 s Bundle
// stays far below the general rate limit (600 per 60 s per address).
// /favicon.ico reads a file and never the store, so its wait is the
// server's isolate alone; /health reads the store, so it also waits for
// the Bundle's transaction, as it would on any one-connection store.
//
// Appends one row per run to cli_starvation_check.tsv, flushed as it runs.
//
// Run from packages/fhirant_server, against a server in --dev-mode:
//   dart run tool/review_2026-10-17/cli_starvation_check.dart \
//     <label> <url> <path> <runs>
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final label = args[0];
  final base = Uri.parse(args[1]);
  final path = args[2];
  final runs = int.parse(args[3]);
  final file = File('tool/review_2026-10-17/cli_starvation_check.tsv');
  final fresh = !file.existsSync();
  final out = file.openSync(mode: FileMode.append);
  if (fresh) {
    out
      ..writeStringSync(
        'label\tpath\trun\tbundle_ms\tbundle_status\tpolls\t'
        'poll_max_ms\tpoll_median_ms\n',
      )
      ..flushSync();
  }
  final client = HttpClient();
  final bundle = jsonEncode({
    'resourceType': 'Bundle',
    'type': 'transaction',
    'entry': [
      for (var i = 0; i < 2000; i++)
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
  for (var run = 0; run < runs; run++) {
    // Each created resource queues a Subscription search after the reply;
    // 30 s lets the previous run's 2,000 clear before this one starts.
    if (run > 0) await Future<void>.delayed(const Duration(seconds: 30));
    var done = false;
    final waits = <int>[];
    final poller = () async {
      while (!done) {
        final clock = Stopwatch()..start();
        final req = await client.getUrl(base.resolve(path));
        final res = await req.close();
        await res.drain<void>();
        waits.add(clock.elapsedMilliseconds);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }();
    final clock = Stopwatch()..start();
    final req = await client.postUrl(base.resolve('/'));
    req.headers
      ..set('content-type', 'application/fhir+json')
      ..set('accept', 'application/fhir+json');
    req.write(bundle);
    final res = await req.close();
    await res.drain<void>();
    final bundleMs = clock.elapsedMilliseconds;
    done = true;
    await poller;
    final sorted = [...waits]..sort();
    final row =
        '$label\t$path\t$run\t$bundleMs\t${res.statusCode}\t${waits.length}\t'
        '${sorted.last}\t${sorted[sorted.length ~/ 2]}';
    out
      ..writeStringSync('$row\n')
      ..flushSync();
    stdout.writeln(row);
  }
  client.close();
  out.closeSync();
}
