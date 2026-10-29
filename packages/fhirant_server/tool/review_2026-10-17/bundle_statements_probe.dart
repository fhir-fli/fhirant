// Why does a transaction Bundle take longer on a background store? On the
// CLI binary a 2,000-entry Bundle took 1.5-1.7 s with SQLite on the
// server's isolate and 3.0-3.4 s with openStoreFile
// (cli_starvation_check.tsv). This counts every statement one Bundle
// sends, by kind and by shape, with the time each took as the server's
// isolate saw it, for both ways of opening the store (each under the real
// cipher setup, applyStoreCipher).
//
// The Subscription worker's searches run after the reply; only statements
// sent while the Bundle request is open are counted.
//
// (Before the held creates: bundle_statements_probe_before.tsv and
// bundle_statements_shapes_before.tsv.)
//
// Writes bundle_statements_probe.tsv (one row per arm, kind) and
// bundle_statements_shapes.tsv (one row per arm, statement shape), each
// flushed as it is written.
//
// Run from packages/fhirant_server:
//   dart run tool/review_2026-10-17/bundle_statements_probe.dart <runs>
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';

import '../../test/integration/test_helpers.dart';

bool _counting = false;
final Map<String, int> _count = {};
final Map<String, int> _micros = {};
final Map<String, int> _shapes = {};

class _Count extends QueryInterceptor {
  Future<T> _time<T>(
    String kind,
    String sql,
    Future<T> Function() run, {
    int times = 1,
  }) async {
    final clock = Stopwatch()..start();
    final result = await run();
    clock.stop();
    if (_counting) {
      _count[kind] = (_count[kind] ?? 0) + times;
      _micros[kind] = (_micros[kind] ?? 0) + clock.elapsedMicroseconds;
      final shape = sql.replaceAll(RegExp(r'\s+'), ' ');
      final key =
          '$kind\t${shape.length > 120 ? shape.substring(0, 120) : shape}';
      _shapes[key] = (_shapes[key] ?? 0) + times;
    }
    return result;
  }

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    if (_counting) _count['begin'] = (_count['begin'] ?? 0) + 1;
    return parent.beginTransaction();
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) =>
      _time('commit', 'COMMIT', inner.send);

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) =>
      _time('select', statement, () => executor.runSelect(statement, args));

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) =>
      _time('insert', statement, () => executor.runInsert(statement, args));

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) =>
      _time('update', statement, () => executor.runUpdate(statement, args));

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) =>
      _time('delete', statement, () => executor.runDelete(statement, args));

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) =>
      _time('custom', statement, () => executor.runCustom(statement, args));

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) =>
      _time(
        'batched',
        statements.statements.join('; '),
        () => executor.runBatched(statements),
        times: statements.arguments.length,
      );
}

Future<void> main(List<String> args) async {
  final runs = int.parse(args.first);
  final kinds = File('tool/review_2026-10-17/bundle_statements_probe.tsv')
      .openSync(mode: FileMode.write)
    ..writeStringSync('arm\trun\tbundle_ms\tkind\tstatements\tmicros\n')
    ..flushSync();
  final shapes = File('tool/review_2026-10-17/bundle_statements_shapes.tsv')
      .openSync(mode: FileMode.write)
    ..writeStringSync('arm\trun\tkind\tshape\tstatements\n')
    ..flushSync();
  for (var run = 0; run < runs; run++) {
    for (final arm in ['same-isolate', 'background']) {
      _count.clear();
      _micros.clear();
      _shapes.clear();
      final dir = await Directory.systemTemp.createTemp('fhirant_bundle_');
      final file = File('${dir.path}/fhirant.db');
      final executor = arm == 'same-isolate'
          ? NativeDatabase(file, setup: (raw) => applyStoreCipher(raw, 'k'))
          : openStoreFile(file, 'k');
      final db = FhirAntDb(executor.interceptWith(_Count()));
      await db.initialize();
      final server = FhirAntServer(db, jwtSecret: testJwtSecret, devMode: true);
      final handler = server.createHandler(server.createRouter());
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
      _counting = true;
      final clock = Stopwatch()..start();
      final r = await handler(
        testRequest(
          'POST',
          '/',
          body: bundle,
          headers: {
            'content-type': 'application/fhir+json',
            'accept': 'application/fhir+json',
          },
        ),
      );
      await r.readAsString();
      clock.stop();
      _counting = false;
      for (final k in _count.keys.toList()..sort()) {
        kinds
          ..writeStringSync(
            '$arm\t$run\t${clock.elapsedMilliseconds}\t$k\t${_count[k]}\t'
            '${_micros[k] ?? ''}\n',
          )
          ..flushSync();
      }
      final top = _shapes.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in top) {
        shapes
          ..writeStringSync('$arm\t$run\t${e.key}\t${e.value}\n')
          ..flushSync();
      }
      stdout.writeln('$arm $run ${clock.elapsedMilliseconds} ms '
          '${r.statusCode}');
      await server.auditQueue.drain();
      await db.close();
      await dir.delete(recursive: true);
    }
  }
  kinds.closeSync();
  shapes.closeSync();
}
