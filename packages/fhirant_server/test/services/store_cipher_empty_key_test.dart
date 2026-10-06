import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;
import 'package:test/test.dart';

/// REVIEW-2026-10-06 finding 2 (probe P7, `tool/review_2026-10-06/`): a
/// store opened through `applyStoreCipher` with an empty key was written in
/// the clear, because `PRAGMA key = ''` is no cipher under sqlite3mc. The
/// file began `SQLite format 3` and a patient's name was readable in it.
/// Here, in fhirant_server, because this package links sqlite3mc; fhirant_db
/// itself links plain SQLite, where every key looks the same
/// (REVIEW-2026-09-17 R1).
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fhirant-empty-key-');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('an empty key is refused before any PRAGMA runs', () {
    // A file, not memory: sqlite3mc refuses PRAGMA key on an in-memory
    // database, which would fail the control for the wrong reason.
    final raw = sqlite3.open('${dir.path}/raw.db');
    try {
      expect(() => applyStoreCipher(raw, ''), throwsArgumentError);
      expect(() => applyStoreCipher(raw, 'a-key'), returnsNormally);
    } finally {
      raw.close();
    }
  });

  test('a store under a real key is not plaintext on disk', () async {
    final file = File('${dir.path}/store.db');
    final db = FhirAntDb(
      NativeDatabase(file, setup: (raw) => applyStoreCipher(raw, 'a-key')),
    );
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
    expect(
      String.fromCharCodes(bytes).contains('PLAINTEXTMARKER'),
      isFalse,
    );
  });

  test('opening a store with an empty key fails, and writes no file', () async {
    final file = File('${dir.path}/empty.db');
    final db = FhirAntDb(
      NativeDatabase(file, setup: (raw) => applyStoreCipher(raw, '')),
    );
    await expectLater(db.initialize(), throwsA(anything));
    await db.close();
    // Whatever the driver left (an empty file at most), nothing was stored.
    expect(
      !file.existsSync() ||
          !String.fromCharCodes(file.readAsBytesSync())
              .startsWith('SQLite format 3'),
      isTrue,
    );
  });
}
