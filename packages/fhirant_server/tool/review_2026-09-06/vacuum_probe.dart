// Does VACUUM INTO under sqlite3mc write an encrypted copy, and under which
// key? Empirical, on the package's own sqlite3 build (native assets).
// ignore_for_file: avoid_print, lines_longer_than_80_chars, cascade_invocations, deprecated_member_use, unnecessary_raw_strings
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

void main(List<String> args) {
  final dir = args[0];
  final src = '$dir/src.sqlite';
  final db = sqlite3.open(src)
    ..execute("PRAGMA cipher = 'sqlcipher'")
    ..execute("PRAGMA key = 'source-passphrase'")
    ..execute('CREATE TABLE t(x TEXT)')
    ..execute("INSERT INTO t VALUES ('hello')");
  print('source cipher: ${db.select('PRAGMA cipher').first.values}');
  // 1. plain VACUUM INTO
  db.execute("VACUUM INTO '$dir/copy_plain.sqlite'");
  // 2. attach with its own key, copy the schema+rows (SQLCipher's sqlcipher_export idea)
  db.execute(
    "ATTACH DATABASE '$dir/copy_attached.sqlite' AS bk KEY 'backup-passphrase'",
  );
  db.execute('CREATE TABLE bk.t AS SELECT * FROM main.t');
  db.execute('DETACH DATABASE bk');
  // 3. sqlite3mc: is there an export function?
  try {
    db.execute("SELECT sqlite3mc_config('cipher')");
    print('sqlite3mc_config available');
  } catch (e) {
    print('no sqlite3mc_config: $e');
  }
  db.dispose();
  for (final (file, key) in [
    ('copy_plain.sqlite', null),
    ('copy_plain.sqlite', 'source-passphrase'),
    ('copy_attached.sqlite', null),
    ('copy_attached.sqlite', 'backup-passphrase'),
  ]) {
    final d = sqlite3.open('$dir/$file');
    try {
      if (key != null) {
        d
          ..execute("PRAGMA cipher = 'sqlcipher'")
          ..execute("PRAGMA key = '$key'");
      }
      final rows = d.select('SELECT x FROM t');
      print('$file key=$key -> readable: ${rows.first.values}');
    } catch (e) {
      print('$file key=$key -> NOT readable ($e)'.split('\n').first);
    }
    d.dispose();
  }
  for (final f in ['src.sqlite', 'copy_plain.sqlite', 'copy_attached.sqlite']) {
    final bytes = File('$dir/$f').readAsBytesSync();
    print(
      '$f header: ${String.fromCharCodes(bytes.take(15)).replaceAll(RegExp(r'[^ -~]'), '.')} (${bytes.length} bytes)',
    );
  }
}
