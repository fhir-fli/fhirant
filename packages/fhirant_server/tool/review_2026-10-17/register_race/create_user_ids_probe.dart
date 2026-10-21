// Whether FhirAntDb.createUser returns the id of the row it inserted when
// calls overlap: it ran INSERT, then `SELECT last_insert_rowid()` as a
// second statement. [count] calls at once, no password hashing in between,
// [repeats] times; each returned id is compared with the row its username
// names. One row per repeat to create_user_ids_probe.tsv, flushed.
//
// Run from packages/fhirant_server:
//   dart run tool/review_2026-10-17/register_race/create_user_ids_probe.dart <count> <repeats>
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';

Future<void> main(List<String> args) async {
  final count = int.parse(args[0]);
  final repeats = int.parse(args[1]);
  final out = File(
    'tool/review_2026-10-17/register_race/create_user_ids_probe.tsv',
  ).openSync(mode: FileMode.write)
    ..writeStringSync('repeat\tcalls\twrong id\n')
    ..flushSync();
  for (var i = 0; i < repeats; i++) {
    final db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
    final names = [for (var k = 0; k < count; k++) 'user$k'];
    final ids = await Future.wait([
      for (final n in names)
        db.createUser(username: n, passwordHash: 'h', salt: 's'),
    ]);
    var wrong = 0;
    for (var k = 0; k < count; k++) {
      if ((await db.getUserByUsername(names[k]))!.id != ids[k]) wrong++;
    }
    final row = '$i\t$count\t$wrong';
    out
      ..writeStringSync('$row\n')
      ..flushSync();
    stdout.writeln(row);
    await db.close();
  }
  out.closeSync();
}
