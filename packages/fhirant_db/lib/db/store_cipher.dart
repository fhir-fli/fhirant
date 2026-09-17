import 'package:sqlite3/sqlite3.dart' show Database;

/// The cipher scheme every FHIRant store and backup is written with.
const storeCipherScheme = 'sqlcipher';

/// The `legacy` parameter of that scheme: 4, the SQLCipher 4 file format.
/// The stores have been opened with it since they moved from
/// sqlcipher_flutter_libs to sqlite3mc, so that the databases those builds
/// created keep opening; a backup is written in the same format, which any
/// SQLCipher 4 tool opens with the passphrase alone.
const storeCipherLegacy = 4;

/// Configures [raw], a connection just opened on a store file, to read and
/// write it under [key]. The ONE place the cipher configuration of a store
/// is written down: the CLI (`bin/server.dart`), the app
/// (`database_service.dart`) and the tests of what they do all call this.
///
/// sqlite3mc SQL Pragmas page (read whole 2026-09-17): "If the encryption
/// scheme is configured via PRAGMA statements, the order of the PRAGMA
/// statements matters": the scheme, then its parameters, then the key.
///
/// The key is a passphrase inside a SQL string literal: a quote in it is
/// doubled, as SQL requires, rather than ending the literal.
void applyStoreCipher(Database raw, String key) {
  raw
    ..execute("PRAGMA cipher = '$storeCipherScheme';")
    ..execute('PRAGMA legacy = $storeCipherLegacy;')
    ..execute("PRAGMA key = '${key.replaceAll("'", "''")}';");
  raw.config.doubleQuotedStringLiterals = false;
}
