// Why is a search slower on a background store? The starvation probe
// (starvation_probe.dart) measured the same search at a median of 4-9 ms
// with SQLite on the server's isolate and 59-70 ms with it on its own
// isolate, while 500 single reads were faster there. This logs every
// statement one search sends, with its time, rows returned and argument
// count, for both arms, after 2,000 Observations are stored.
//
// One row per statement to search_statements_probe.tsv, flushed as it runs.
//
// Run from packages/fhirant_server:
//   dart run tool/review_2026-10-17/search_statements_probe.dart
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';

import '../../test/integration/test_helpers.dart';

late RandomAccessFile _out;
String _arm = '';
int _search = -1;

class _Log extends QueryInterceptor {
  Future<T> _time<T>(
    String kind,
    String sql,
    List<Object?> args,
    Future<T> Function() run,
  ) async {
    final clock = Stopwatch()..start();
    final result = await run();
    clock.stop();
    if (_search >= 0) {
      final rows = result is List ? result.length : '';
      final oneLine = sql.replaceAll(RegExp(r'\s+'), ' ');
      _out
        ..writeStringSync('$_arm\t$_search\t$kind\t'
            '${clock.elapsedMicroseconds}\t$rows\t${args.length}\t'
            '${oneLine.length > 300 ? oneLine.substring(0, 300) : oneLine}\n')
        ..flushSync();
    }
    return result;
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) =>
      _time(
        'select',
        statement,
        args,
        () => executor.runSelect(statement, args),
      );

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) =>
      _time(
        'custom',
        statement,
        args,
        () => executor.runCustom(statement, args),
      );
}

Future<void> main() async {
  _out = File('tool/review_2026-10-17/search_statements_probe.tsv')
      .openSync(mode: FileMode.write)
    ..writeStringSync('arm\tsearch\tkind\tmicros\trows\targs\tsql\n')
    ..flushSync();
  for (final arm in ['cli', 'app']) {
    _arm = arm;
    _search = -1;
    final dir = await Directory.systemTemp.createTemp('fhirant_stmts_');
    final file = File('${dir.path}/fhirant.db');
    final executor = arm == 'cli'
        ? NativeDatabase(file)
        : NativeDatabase.createInBackground(file);
    final db = FhirAntDb(executor.interceptWith(_Log()));
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
    await handler(testRequest('POST', '/', body: bundle, headers: json));
    // Every request queues an AuditEvent, written in batches off the
    // response path (AuditQueue). Each search is timed with the queue
    // empty, so it measures the search and not a batch written beside it.
    // Search 0 is the first after the write; 1-4 are steady state.
    for (_search = 0; _search < 5; _search++) {
      final searchNo = _search;
      _search = -1;
      await server.auditQueue.drain();
      _search = searchNo;
      final clock = Stopwatch()..start();
      final r = await handler(
        testRequest(
          'GET',
          '/Observation?status=final&_count=50',
          headers: json,
        ),
      );
      await r.readAsString();
      clock.stop();
      _out
        ..writeStringSync('$arm\t$_search\tHTTP\t'
            '${clock.elapsedMicroseconds}\t\t\t${r.statusCode}\n')
        ..flushSync();
    }
    _search = -1;
    await server.auditQueue.drain();
    await db.close();
    await dir.delete(recursive: true);
  }
  _out.closeSync();
}
