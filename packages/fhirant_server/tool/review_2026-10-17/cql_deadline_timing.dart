// How long do program_sandbox_test's two CQL programs take with no deadline
// pressure? Picks a deadline the slow one cannot meet and the small one
// always can. One line per run to cql_deadline_timing.tsv.
// Run from packages/fhirant_server:
//   dart run tool/review_2026-10-17/cql_deadline_timing.dart
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/cql_handler.dart';
import 'package:shelf/shelf.dart';

Future<void> main() async {
  final out = File('tool/review_2026-10-17/cql_deadline_timing.tsv');
  if (!out.existsSync()) {
    out.writeAsStringSync('program\trun\tms\tstatus\n', flush: true);
  }
  final db = FhirAntDb(NativeDatabase.memory());
  await db.initialize();
  const ten = '{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}';
  const slow = "library P version '1.0.0'\n"
      'define X: Count(from ($ten) A, ($ten) B, ($ten) C, ($ten) D, '
      '($ten) E, ($ten) F, ($ten) G return 1)';
  const small = "library P version '1.0.0'\ndefine X: 1 + 1";
  final defines = StringBuffer("library L version '1'\ncontext Patient\n");
  for (var i = 0; i < 4000; i++) {
    defines.writeln('define D$i: $i + $i * 2 - 1');
  }
  final only = Platform.environment['PROGRAMS']?.split(',');
  for (final (name, source, runs) in [
    ('small', small, 10),
    ('slow', slow, 2),
    ('4000-defines', defines.toString(), 3),
  ]) {
    if (only != null && !only.contains(name)) continue;
    for (var i = 0; i < runs; i++) {
      final sw = Stopwatch()..start();
      final r = await cqlHandler(
        Request(
          'POST',
          Uri.parse(r'http://localhost:8080/$cql'),
          body: jsonEncode({'cql': source}),
        ),
        db,
        deadline: const Duration(seconds: 120),
      );
      sw.stop();
      final line = '$name\t$i\t${sw.elapsedMilliseconds}\t${r.statusCode}\n';
      out.writeAsStringSync(line, mode: FileMode.append, flush: true);
      stdout.write(line);
    }
  }
  await db.close();
  exit(0);
}
