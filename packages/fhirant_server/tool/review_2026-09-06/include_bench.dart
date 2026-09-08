// REVIEW-2026-09-06 finding 39: `_include` (one read per target, then one
// per type) and `_revinclude` (every referrer, then the page's budget) on
// the MIMIC copy, through the server handler.
//
//   dart run tool/review_2026-09-06/include_bench.dart <dir> <tsv> <label> include|include500|revinclude
//
// Appends one row: label, case, ms, match entries, include entries, outcome
// entries, RSS MB at the end, RSS MB after opening the store.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/fhirant_server.dart';
import 'package:shelf/shelf.dart' as shelf;

Future<void> main(List<String> args) async {
  final dir = args[0];
  final tsv = File(args[1]);
  final label = args[2];
  final which = args[3];
  if (!tsv.existsSync()) {
    tsv.writeAsStringSync(
      'label\tcase\tms\tmatches\tincludes\toutcomes\trss_mb\trss_open_mb\n',
    );
  }
  final db = FhirAntDb(NativeDatabase(File('$dir/fhirant.sqlite')));
  await db.initialize();
  final rssOpen = ProcessInfo.currentRss ~/ (1024 * 1024);
  final server = FhirAntServer(db, jwtSecret: 'bench', devMode: true);
  final handler = server.createHandler(server.createRouter());
  final path = switch (which) {
    'include' => '/Observation?_include=Observation:*&_count=100&_total=none',
    'include500' =>
      '/Observation?_include=Observation:*&_count=500&_total=none',
    _ => '/Patient?_revinclude=Observation:patient&_count=5&_total=none',
  };
  final sw = Stopwatch()..start();
  final response = await handler(
    shelf.Request(
      'GET',
      Uri.parse('http://localhost:8080$path'),
      headers: {'x-forwarded-for': '127.0.0.1'},
    ),
  );
  final body =
      jsonDecode(await response.readAsString()) as Map<String, dynamic>;
  sw.stop();
  final modes = <String, int>{};
  for (final e in (body['entry'] as List? ?? const [])) {
    final mode = ((e as Map<String, dynamic>)['search']
            as Map<String, dynamic>?)?['mode'] as String? ??
        '?';
    modes[mode] = (modes[mode] ?? 0) + 1;
  }
  final rss = ProcessInfo.currentRss ~/ (1024 * 1024);
  final row =
      '$label\t$which\t${sw.elapsedMilliseconds}\t${modes['match'] ?? 0}\t'
      '${modes['include'] ?? 0}\t${modes['outcome'] ?? 0}\t$rss\t$rssOpen\n';
  tsv.writeAsStringSync(row, mode: FileMode.append);
  stdout.write('status ${response.statusCode} $row');
  await db.close();
  exit(0);
}
