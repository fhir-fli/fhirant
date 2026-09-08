// How long does an ATTACH ... KEY copy of the whole database take, table by
// table from sqlite_master, on the MIMIC copy? Writes <dir>/attach_copy.tsv.
// ignore_for_file: avoid_print, lines_longer_than_80_chars, cascade_invocations, deprecated_member_use, avoid_multiple_declarations_per_line, require_trailing_commas
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

void main(List<String> args) {
  final src = args[0], out = args[1];
  final tsv = File('$out.tsv')..writeAsStringSync('step\tms\tnote\n');
  void row(String s, int ms, [String n = '']) {
    final rss = ProcessInfo.currentRss ~/ (1024 * 1024);
    tsv.writeAsStringSync('$s\t$ms\t$n rss=${rss}MB\n', mode: FileMode.append);
    print('$s: ${ms}ms $n rss=${rss}MB');
  }

  final db = sqlite3.open(src)..execute("PRAGMA cipher = 'sqlcipher'");
  if (File(out).existsSync()) File(out).deleteSync();
  final sw = Stopwatch()..start();
  db.execute("ATTACH DATABASE '$out' AS bk KEY 'backup-passphrase'");
  row('attach', sw.elapsedMilliseconds);
  final master = db.select(
      "SELECT type, name, tbl_name, sql FROM main.sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY CASE type WHEN 'table' THEN 0 ELSE 1 END, name");
  var total = 0;
  for (final m in master) {
    if (m['type'] != 'table') continue;
    final name = m['name'] as String;
    final sql = (m['sql'] as String).replaceFirst(
      RegExp('^CREATE TABLE\\s+(IF NOT EXISTS\\s+)?"?${RegExp.escape(name)}"?'),
      'CREATE TABLE bk."$name"',
    );
    final t = Stopwatch()..start();
    db.execute(sql);
    db.execute('INSERT INTO bk."$name" SELECT * FROM main."$name"');
    final n =
        db.select('SELECT count(*) AS c FROM bk."$name"').first['c'] as int;
    total += n;
    row('table $name', t.elapsedMilliseconds, '$n rows');
  }
  for (final m in master) {
    if (m['type'] != 'index') continue;
    final name = m['name'] as String;
    final sql = (m['sql'] as String).replaceFirstMapped(
      RegExp(
          '^CREATE (UNIQUE )?INDEX\\s+(IF NOT EXISTS\\s+)?"?${RegExp.escape(name)}"?'),
      (mm) => 'CREATE ${mm.group(1) ?? ''}INDEX bk."$name"',
    );
    final t = Stopwatch()..start();
    db.execute(sql);
    row('index $name', t.elapsedMilliseconds);
  }
  db.execute(
      'PRAGMA bk.user_version = ${db.select('PRAGMA main.user_version').first.values.first}');
  db.execute('DETACH DATABASE bk');
  row('total', sw.elapsedMilliseconds,
      '$total rows, ${File(out).lengthSync()} bytes');
  db.dispose();
  final t = Stopwatch()..start();
  final check = sqlite3.open(out)
    ..execute("PRAGMA cipher = 'sqlcipher'")
    ..execute("PRAGMA key = 'backup-passphrase'");
  final n = check.select('SELECT count(*) AS c FROM resources').first['c'];
  row('reopen with passphrase: resources', t.elapsedMilliseconds, '$n');
  check.dispose();
}
