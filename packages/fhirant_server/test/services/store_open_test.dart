import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:test/test.dart';

/// OWASP ASVS 5.0.0 V15.4.4 (REVIEW-2026-10-17): the CLI opened its store
/// with SQLite on the server's isolate, so no other request was answered
/// during a 2,000-entry transaction Bundle (1.09-1.21 s,
/// `tool/review_2026-10-17/starvation_probe.tsv`). `openStoreFile` is the
/// one way the CLI and the app open their store; it must leave the calling
/// isolate free while a statement runs. Here, in fhirant_server, because
/// this package links sqlite3mc (see store_cipher_empty_key_test.dart).
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fhirant-store-open-');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  // One statement that keeps SQLite busy for a few hundred milliseconds.
  const longStatement = 'WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL '
      'SELECT x + 1 FROM c WHERE x < 3000000) SELECT count(*) FROM c';

  /// Runs [longStatement] on [executor] and counts the ticks a 10 ms timer
  /// on this isolate gets while it runs.
  Future<({int ticks, int ms})> ticksDuring(QueryExecutor executor) async {
    final db = FhirAntDb(executor);
    await db.initialize();
    var ticks = 0;
    final clock = Stopwatch()..start();
    final ticker =
        Timer.periodic(const Duration(milliseconds: 10), (_) => ticks++);
    await db.customSelect(longStatement).get();
    clock.stop();
    ticker.cancel();
    await db.close();
    return (ticks: ticks, ms: clock.elapsedMilliseconds);
  }

  test('a long statement does not hold the calling isolate', () async {
    final r = await ticksDuring(
      openStoreFile(File('${dir.path}/store.db'), 'a-key'),
    );
    // A free isolate ticks about once per 10 ms; a quarter of that is
    // well clear of zero, which is what a held isolate gets.
    expect(r.ms, greaterThan(100), reason: 'the statement must be long');
    expect(r.ticks, greaterThan(r.ms ~/ 40), reason: '$r');
  });

  test('control: the same statement on the calling isolate holds it', () async {
    final file = File('${dir.path}/control.db');
    final r = await ticksDuring(
      NativeDatabase(file, setup: (raw) => applyStoreCipher(raw, 'a-key')),
    );
    expect(r.ms, greaterThan(100), reason: 'the statement must be long');
    expect(r.ticks, 0, reason: '$r');
  });

  test('the store it opens is under the key, not plaintext', () async {
    final file = File('${dir.path}/store.db');
    final db = FhirAntDb(openStoreFile(file, 'a-key'));
    await db.initialize();
    await db.saveResource(
      fhir.Patient(
        id: fhir.FhirString('p1'),
        name: [fhir.HumanName(family: fhir.FhirString('PLAINTEXTMARKER'))],
      ),
    );
    await db.close();
    final bytes = file.readAsBytesSync();
    expect(String.fromCharCodes(bytes.take(15)), isNot('SQLite format 3'));
    expect(String.fromCharCodes(bytes).contains('PLAINTEXTMARKER'), isFalse);
  });

  test('an empty key fails the open on the store isolate too', () async {
    final file = File('${dir.path}/empty.db');
    final db = FhirAntDb(openStoreFile(file, ''));
    await expectLater(db.initialize(), throwsA(anything));
    await db.close();
    expect(
      !file.existsSync() ||
          !String.fromCharCodes(file.readAsBytesSync())
              .startsWith('SQLite format 3'),
      isTrue,
    );
  });
}
