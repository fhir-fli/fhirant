// REVIEW-2026-09-06 finding 37: what a POST costs while a rest-hook
// subscriber is slow. An in-memory server with one active rest-hook
// Subscription on Observation, a local HTTP endpoint that answers each hook
// after <hook_ms>, and <n> sequential POSTs of matching Observations.
//
//   dart run tool/review_2026-09-06/subscription_latency_bench.dart <tsv> <label> [n] [hook_ms]
//
// Appends one row: label, n, hook_ms, POST p50 ms, POST max ms, ms until all
// hooks were received, hooks received.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/fhirant_server.dart';
import 'package:shelf/shelf.dart' as shelf;

Future<void> main(List<String> args) async {
  final tsv = File(args[0]);
  final label = args[1];
  final n = args.length > 2 ? int.parse(args[2]) : 20;
  final hookMs = args.length > 3 ? int.parse(args[3]) : 500;
  if (!tsv.existsSync()) {
    tsv.writeAsStringSync(
      'label\tn\thook_ms\tpost_p50_ms\tpost_max_ms\tall_hooks_ms\thooks\n',
    );
  }

  var hooks = 0;
  final endpoint = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  endpoint.listen((req) async {
    await Future<void>.delayed(Duration(milliseconds: hookMs));
    hooks++;
    req.response.statusCode = 200;
    await req.response.close();
  });

  final db = FhirAntDb(NativeDatabase.memory());
  await db.initialize();
  final server = FhirAntServer(db, jwtSecret: 'bench', devMode: true);
  final handler = server.createHandler(server.createRouter());

  shelf.Request post(String path, Map<String, dynamic> body) => shelf.Request(
        'POST',
        Uri.parse('http://localhost:8080$path'),
        body: jsonEncode(body),
        headers: {
          'content-type': 'application/fhir+json',
          'x-forwarded-for': '127.0.0.1',
        },
      );

  final sub = await handler(
    post('/Subscription', {
      'resourceType': 'Subscription',
      'status': 'requested',
      'reason': 'bench',
      'criteria': 'Observation?status=final',
      'channel': {
        'type': 'rest-hook',
        'endpoint': 'http://127.0.0.1:${endpoint.port}/hook',
      },
    }),
  );
  stdout.writeln('subscription: ${sub.statusCode} ${await sub.readAsString()}');

  final total = Stopwatch()..start();
  final latencies = <int>[];
  for (var i = 0; i < n; i++) {
    final sw = Stopwatch()..start();
    final r = await handler(
      post('/Observation', {
        'resourceType': 'Observation',
        'status': 'final',
        'code': {'text': 'bench $i'},
      }),
    );
    await r.readAsString();
    latencies.add(sw.elapsedMilliseconds);
    stdout.writeln('post $i: ${r.statusCode} ${sw.elapsedMilliseconds} ms');
  }
  while (hooks < n && total.elapsedMilliseconds < 120000) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  total.stop();
  latencies.sort();
  final row = '$label\t$n\t$hookMs\t${latencies[latencies.length ~/ 2]}\t'
      '${latencies.last}\t${total.elapsedMilliseconds}\t$hooks\n';
  tsv.writeAsStringSync(row, mode: FileMode.append);
  stdout.write(row);
  await server.stop();
  await endpoint.close(force: true);
  await db.close();
  exit(0);
}
