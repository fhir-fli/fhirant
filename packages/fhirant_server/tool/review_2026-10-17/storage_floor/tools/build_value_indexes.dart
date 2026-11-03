// Times createValueIndexes on a loaded database: the build-at-the-end half
// of load_then_index.sh, whose load skipped the covering indexes (fhir_db
// eccd67c with fhir_db_narrow_switch.patch, FHIR_DB_NARROW=2).
//
// Usage: dart run <this file> <db dir>
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';

Future<void> main(List<String> args) async {
  final db = FhirAntDb(NativeDatabase(File('${args[0]}/fhirant.sqlite')));
  final t = Stopwatch()..start();
  await db.createValueIndexes();
  final seconds = (t.elapsedMilliseconds / 1000).toStringAsFixed(1);
  print('createValueIndexes: ${seconds}s');
  await db.close();
}
