// REVIEW-2026-09-06 finding 40: what the audit trail costs on the disk-backed
// MIMIC copy. <n> audited GET /Patient/<id> requests through the server
// handler, then the wait until <n> new AuditEvents are stored.
//
//   dart run tool/review_2026-09-06/audit_bench.dart <dir> <tsv> <label> [n]
//
// Appends one row: label, n, ms for the requests, ms until all events are
// stored (from the first request), events stored, RSS MB.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/fhirant_server.dart';
import 'package:shelf/shelf.dart' as shelf;

Future<void> main(List<String> args) async {
  final dir = args[0];
  final tsv = File(args[1]);
  final label = args[2];
  final n = args.length > 3 ? int.parse(args[3]) : 200;
  if (!tsv.existsSync()) {
    tsv.writeAsStringSync(
      'label\tn\trequests_ms\tall_stored_ms\tstored\trss_mb\n',
    );
  }
  final db = FhirAntDb(NativeDatabase(File('$dir/fhirant.sqlite')));
  await db.initialize();
  final before = await db.getResourceCount(fhir.R4ResourceType.AuditEvent);
  final patients = await db.search(
    resourceType: fhir.R4ResourceType.Patient,
    searchParameters: const {},
    count: n,
  );
  final ids = [for (final p in patients) p.id!.valueString!];
  final server = FhirAntServer(db, jwtSecret: 'bench', devMode: true);
  final handler = server.createHandler(server.createRouter());

  final total = Stopwatch()..start();
  for (var i = 0; i < n; i++) {
    final r = await handler(
      shelf.Request(
        'GET',
        Uri.parse('http://localhost:8080/Patient/${ids[i % ids.length]}'),
        headers: {'x-forwarded-for': '127.0.0.1'},
      ),
    );
    await r.readAsString();
  }
  final requestsMs = total.elapsedMilliseconds;
  var stored = 0;
  while (total.elapsedMilliseconds < 120000) {
    stored = await db.getResourceCount(fhir.R4ResourceType.AuditEvent) - before;
    if (stored >= n) break;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  total.stop();
  final row = '$label\t$n\t$requestsMs\t${total.elapsedMilliseconds}\t$stored\t'
      '${ProcessInfo.currentRss ~/ (1024 * 1024)}\n';
  tsv.writeAsStringSync(row, mode: FileMode.append);
  stdout.write(row);
  await server.stop().catchError((_) {});
  await db.close();
  exit(0);
}
