// What a running $export costs concurrent requests, measured through the
// server's own handler on one isolate: read latency at rest, then read
// latency while a system-level export of every resource streams to disk
// (REVIEW-2026-09-06 "export isolate", measured before deciding).
//
//   dart run tool/review_2026-09-06/export_contention_bench.dart \
//     tool/review_2026-09-06/export_contention_bench.tsv <label> \
//     [observations=100000] [existing fhirant.sqlite|-] [read_interval_ms=0]
//
// With an existing store, its resources are exported; otherwise a store is
// built in a temp dir with the given number of Observations and kept (its
// path is printed) for the next run. `read_interval_ms` spaces the reads
// made during the export: 0 is back to back, 100 is ten a second. Rows are
// appended and flushed as they are measured.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/fhirant_server.dart';
import 'package:shelf/shelf.dart' as shelf;

Future<void> main(List<String> args) async {
  final tsv = File(args[0]);
  final label = args[1];
  final observations = args.length > 2 ? int.parse(args[2]) : 100000;
  final existing = args.length > 3 && args[3] != '-' ? args[3] : null;
  final readInterval = Duration(
    milliseconds: args.length > 4 ? int.parse(args[4]) : 0,
  );
  if (!tsv.existsSync()) {
    tsv.writeAsStringSync(
      'label\tphase\tread_interval_ms\tresources\treads\tread_p50_ms'
      '\tread_p95_ms\tread_max_ms\texport_ms\texport_files\n',
    );
  }
  void row(
    String phase,
    int resources,
    List<double> samples,
    int exportMs,
    int files,
  ) {
    samples.sort();
    final p95 =
        samples[(samples.length * 0.95).floor().clamp(0, samples.length - 1)];
    final line = '$label\t$phase\t${readInterval.inMilliseconds}\t'
        '$resources\t${samples.length}\t'
        '${samples[samples.length ~/ 2].toStringAsFixed(2)}\t'
        '${p95.toStringAsFixed(2)}\t'
        '${samples.last.toStringAsFixed(2)}\t$exportMs\t$files\n';
    tsv.writeAsStringSync(line, mode: FileMode.append, flush: true);
    stdout.write(line);
  }

  final dir = Directory.systemTemp.createTempSync('fhirant_export_contention_');
  final dbPath = existing ?? '${dir.path}/fhirant.sqlite';
  final db = FhirAntDb(NativeDatabase(File(dbPath)));
  await db.initialize();
  if (existing == null) {
    final sw = Stopwatch()..start();
    for (var start = 0; start < observations; start += 1000) {
      await db.saveResources([
        for (var i = start; i < start + 1000; i++)
          fhir.Observation.fromJson({
            'resourceType': 'Observation',
            'id': 'o$i',
            'status': 'final',
            'code': {
              'coding': [
                {'system': 'http://loinc.org', 'code': '8480-6'},
              ],
            },
            'subject': {'reference': 'Patient/p${i % 1000}'},
            'effectiveDateTime':
                '2024-01-${(i % 28 + 1).toString().padLeft(2, '0')}T10:00:00Z',
            'valueQuantity': {'value': 100 + i % 60, 'code': 'mm[Hg]'},
          }),
      ]);
      if (start % 20000 == 0) {
        stdout.writeln('loaded $start in ${sw.elapsed.inSeconds}s');
      }
    }
    stdout.writeln('loaded $observations in ${sw.elapsed.inSeconds}s');
  }
  final total = await db.getResourceCount(fhir.R4ResourceType.Observation);

  // The general limiter (600/min per address) would refuse the reads; the
  // in-process request has no connection address, so every read shares one
  // bucket. Raised out of the way: the store is what is measured.
  final server = FhirAntServer(
    db,
    jwtSecret: 'bench',
    devMode: true,
    exportDir: '${dir.path}/exports',
    maxRequests: 1000000,
  );
  final handler = server.createHandler(server.createRouter());
  // The general limiter is per client address (600/min); the reads here
  // come from many addresses so they measure the store, not the limiter.
  shelf.Request get(
    String path, {
    Map<String, String>? headers,
    String ip = '127.0.0.1',
  }) =>
      shelf.Request(
        'GET',
        Uri.parse('http://localhost:8080$path'),
        headers: {'x-forwarded-for': ip, ...?headers},
      );

  Future<double> oneRead(int i) async {
    // A real request arrives from a socket, an event-queue task; between two
    // of them the loop drains. An in-process read completes in microtasks,
    // and a tight loop of those starves every event-queue task the export
    // needs (its file writes never ran: measured 2026-09-10, no output
    // directory after 628 s). One turn of the loop per read models the
    // socket boundary.
    await Future<void>.delayed(Duration.zero);
    final sw = Stopwatch()..start();
    final r = await handler(
      get(
        '/Observation/o${(i * 7919) % total}',
        ip: '10.${(i ~/ 200) % 250}.${i % 250}.1',
      ),
    );
    await r.readAsString();
    sw.stop();
    if (r.statusCode != 200) throw StateError('read ${r.statusCode}');
    return sw.elapsedMicroseconds / 1000;
  }

  // At rest.
  const reads = 300;
  final idle = <double>[];
  for (var i = 0; i < reads; i++) {
    idle.add(await oneRead(i));
  }
  row('idle', total, idle, 0, 0);

  // The export alone: kicked off and polled every 100 ms, no reads.
  Future<(int, int)> runExport() async {
    final kick = await handler(
      get(r'/$export?_type=Observation', headers: {'prefer': 'respond-async'}),
    );
    if (kick.statusCode != 202) {
      throw StateError(
        'kickoff ${kick.statusCode} ${await kick.readAsString()}',
      );
    }
    final poll = kick.headers['content-location']!
        .replaceFirst(RegExp('^https?://[^/]+'), '');
    final sw = Stopwatch()..start();
    while (true) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final p = await handler(get(poll, ip: '10.250.250.1'));
      final body = await p.readAsString();
      if (p.statusCode == 200) {
        return (
          sw.elapsedMilliseconds,
          ((jsonDecode(body) as Map)['output'] as List).length
        );
      }
      if (p.statusCode != 202) throw StateError('poll ${p.statusCode} $body');
    }
  }

  final (aloneMs, aloneFiles) = await runExport();
  row('export_alone', total, [0], aloneMs, aloneFiles);

  // During the export: kick off, then read until it completes.
  final kick = await handler(
    get(r'/$export?_type=Observation', headers: {'prefer': 'respond-async'}),
  );
  if (kick.statusCode != 202) {
    throw StateError('kickoff ${kick.statusCode} ${await kick.readAsString()}');
  }
  final poll = kick.headers['content-location']!
      .replaceFirst(RegExp('^https?://[^/]+'), '');
  final exportSw = Stopwatch()..start();
  final during = <double>[];
  var files = 0;
  var i = 0;
  while (true) {
    if (readInterval > Duration.zero) await Future<void>.delayed(readInterval);
    during.add(await oneRead(i++));
    if (i % 25 == 0) {
      final p = await handler(get(poll, ip: '10.250.250.1'));
      final body = await p.readAsString();
      if (p.statusCode == 200) {
        exportSw.stop();
        files = ((jsonDecode(body) as Map)['output'] as List).length;
        break;
      }
      if (p.statusCode != 202) throw StateError('poll ${p.statusCode} $body');
    }
  }
  row('during_export', total, during, exportSw.elapsedMilliseconds, files);

  // At rest again, same process, so a warm/cold difference shows.
  final after = <double>[];
  for (var i = 0; i < reads; i++) {
    after.add(await oneRead(i));
  }
  row('idle_after', total, after, 0, 0);

  await server.stop();
  await db.close();
  stdout.writeln('store: $dbPath');
}
