import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/cql_handler.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// REVIEW-2026-10-06 finding 14 (probe P13): CQL was translated on the
/// server isolate, outside the program deadline A9 put on execution; 15 KB
/// of CQL held every other request 915 ms, 269 KB 5.3 s, linear, under a
/// 16 MiB body cap. Translation runs in the worker isolate now, and a
/// translation past the deadline is 422 too-costly like an execution.
void main() {
  late FhirAntDb db;

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
  });

  tearDown(() => db.close());

  Request cql(String source) => Request(
        'POST',
        Uri.parse(r'http://localhost:8080/$cql'),
        body: jsonEncode({'cql': source}),
      );

  String defines(int n) {
    final sb = StringBuffer("library L version '1'\ncontext Patient\n");
    for (var i = 0; i < n; i++) {
      sb.writeln('define D$i: $i + $i * 2 - 1');
    }
    return sb.toString();
  }

  test('a translation that outruns the deadline is 422 too-costly', () async {
    final response = await cqlHandler(
      cql(defines(2000)),
      db,
      deadline: const Duration(milliseconds: 1),
    );
    expect(response.statusCode, 422);
    expect(await response.readAsString(), contains('too-costly'));
  });

  test('a long translation does not hold the server isolate', () async {
    // The finding itself: with the translation on the server isolate a
    // 100 ms timer fired only after it (about 2.7 s for 4,000 defines on
    // the review's desktop, P13). Off the isolate it fires on time.
    final started = Stopwatch()..start();
    final timer = Future<void>.delayed(const Duration(milliseconds: 100))
        .then((_) => started.elapsedMilliseconds);
    final response = cqlHandler(cql(defines(4000)), db);
    final firedAt = await timer;
    expect(firedAt, lessThan(1000), reason: 'the timer waited $firedAt ms');
    expect((await response).statusCode, 200);
  });

  test('control: a small library translates and runs', () async {
    final response = await cqlHandler(cql(defines(3)), db);
    expect(response.statusCode, 200, reason: await response.readAsString());
  });

  test('CQL that does not translate is still 400', () async {
    final response =
        await cqlHandler(cql("library L version '1'\ndefine X: ("), db);
    expect(response.statusCode, 400);
  });
}
