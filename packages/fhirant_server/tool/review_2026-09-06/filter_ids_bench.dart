// REVIEW-2026-09-06 finding 38: a `_filter` leaf on the MIMIC copy, the old
// way (every matching resource read, its id taken) against `searchIds`, and
// the whole `GET /Observation?_filter=status eq final&_count=20` through the
// server handler on the new code.
//
//   dart run tool/review_2026-09-06/filter_ids_bench.dart <dir> <tsv> old-leaf|new-leaf|e2e
//
// Appends one row per run: mode, ms, ids or entries, RSS MB at the end, RSS
// MB after opening the store.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/fhirant_server.dart';
import 'package:shelf/shelf.dart' as shelf;

Future<void> main(List<String> args) async {
  final dir = args[0];
  final tsv = File(args[1]);
  final mode = args[2];
  if (!tsv.existsSync()) {
    tsv.writeAsStringSync('mode\tms\tn\trss_mb\trss_open_mb\n');
  }
  final db = FhirAntDb(NativeDatabase(File('$dir/fhirant.sqlite')));
  await db.initialize();
  final rssOpen = ProcessInfo.currentRss ~/ (1024 * 1024);
  final sw = Stopwatch()..start();
  int n;
  switch (mode) {
    case 'old-leaf':
      // filter_evaluator.dart before 2026-09-08: the leaf ran the full
      // search with no page and took the id off every resource.
      final matches = await db.search(
        resourceType: fhir.R4ResourceType.Observation,
        searchParameters: {
          'status': ['final'],
        },
      );
      n = matches
          .map((r) => r.id?.valueString)
          .whereType<String>()
          .toSet()
          .length;
    case 'new-leaf':
      n = (await db.searchIds(
        resourceType: fhir.R4ResourceType.Observation,
        searchParameters: {
          'status': ['final'],
        },
      ))
          .length;
    case 'e2e':
      final server = FhirAntServer(db, jwtSecret: 'bench', devMode: true);
      final handler = server.createHandler(server.createRouter());
      final response = await handler(
        shelf.Request(
          'GET',
          Uri.parse(
            'http://localhost:8080/Observation?_filter=status%20eq%20final&_count=20',
          ),
          headers: {'x-forwarded-for': '127.0.0.1'},
        ),
      );
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      stdout.writeln('status ${response.statusCode}, total ${body['total']}');
      n = (body['entry'] as List?)?.length ?? 0;
    default:
      throw ArgumentError(mode);
  }
  sw.stop();
  final rss = ProcessInfo.currentRss ~/ (1024 * 1024);
  final row = '$mode\t${sw.elapsedMilliseconds}\t$n\t$rss\t$rssOpen\n';
  tsv.writeAsStringSync(row, mode: FileMode.append);
  stdout.write(row);
  await db.close();
  exit(0);
}
