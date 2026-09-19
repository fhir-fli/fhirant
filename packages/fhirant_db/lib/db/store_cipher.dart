import 'package:sqlite3/sqlite3.dart' show Database;

/// The cipher scheme every FHIRant store and backup is written with.
const storeCipherScheme = 'sqlcipher';

/// The `legacy` parameter of that scheme: 4, the SQLCipher 4 file format.
/// The stores have been opened with it since they moved from
/// sqlcipher_flutter_libs to sqlite3mc, so that the databases those builds
/// created keep opening; a backup is written in the same format, which any
/// SQLCipher 4 tool opens with the passphrase alone.
const storeCipherLegacy = 4;

/// The store's journal mode: write-ahead logging.
///
/// Measured 2026-09-17 on the review's desktop, 200 single-resource commits
/// (`fhirant_server/tool/review_2026-09-17/store_probe2.tsv`): rollback
/// journal with `synchronous=FULL` 23.8 ms per commit; WAL with FULL
/// 8.5 ms; WAL with NORMAL 0.5 ms. FULL is kept (below): the same
/// durability as before at about a third of the cost. NORMAL would be
/// faster still and "WAL mode does lose durability. A transaction
/// committed in WAL mode with synchronous=NORMAL might roll back following
/// a power loss" (sqlite.org/pragma.html, `synchronous` section, read whole
/// 2026-09-18); losing a clinician's last writes is a clinical call, not
/// made here.
const storeJournalMode = 'WAL';

/// The store's `synchronous` setting. "FULL is atomic, consistent,
/// isolated, and durable (ACID) in WAL mode" (sqlite.org/pragma.html,
/// `synchronous` section, verbatim, read whole 2026-09-18).
const storeSynchronous = 'FULL';

/// Configures [raw], a connection just opened on a store file: the cipher
/// it is read and written under [key], then its journal mode and sync
/// level. The ONE place the configuration of a store is written down: the
/// CLI (`bin/server.dart`), the app (`database_service.dart`) and the tests
/// of what they do all call this.
///
/// sqlite3mc SQL Pragmas page (read whole 2026-09-17): "If the encryption
/// scheme is configured via PRAGMA statements, the order of the PRAGMA
/// statements matters": the scheme, then its parameters, then the key. The
/// journal mode comes after the key: setting it writes the file header,
/// which only a keyed connection can.
///
/// Both journal PRAGMAs name `main`. sqlite.org/pragma.html, `journal_mode`
/// section, verbatim (read whole 2026-09-18): "The second form changes the
/// journaling mode for "database" or for all attached databases if
/// "database" is omitted." A backup is ATTACHed to this connection and
/// must stay one plain file, so the mode is the store's alone. WAL "is
/// persistent; after being set it stays in effect across multiple database
/// connections and after closing and reopening the database" (same
/// section, verbatim); `synchronous` is per connection, so both are set on
/// every open.
///
/// The key is a passphrase inside a SQL string literal: a quote in it is
/// doubled, as SQL requires, rather than ending the literal.
void applyStoreCipher(Database raw, String key) {
  raw
    ..execute("PRAGMA cipher = '$storeCipherScheme';")
    ..execute('PRAGMA legacy = $storeCipherLegacy;')
    ..execute("PRAGMA key = '${key.replaceAll("'", "''")}';")
    ..execute('PRAGMA main.journal_mode = $storeJournalMode;')
    ..execute('PRAGMA main.synchronous = $storeSynchronous;');
  raw.config.doubleQuotedStringLiterals = false;
}
