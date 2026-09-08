import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhir_r4_db/fhir_r4_db.dart';
import 'package:fhirant_db/db/server_types.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;

/// FHIR ANT server database.
///
/// Extends [FhirDb] (from fhir_r4_db) to reuse all FHIR CRUD, search, history,
/// and search parameter indexing logic. Adds server-specific functionality:
/// Users, ExportJobs, and Logs tables (managed via raw SQL).
class FhirAntDb extends FhirDb {
  FhirAntDb(super.e) {
    // Server uses integer version IDs (1, 2, 3, ...).
    fhirDao.versionIdAsTime = false;
  }

  @override
  int get schemaVersion => 18;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll(); // Creates FhirDb's 14 tables
          await _createUsersTable();
          await _createExportJobsTable();
          await _createLogsTable();
          await _createAuthorizationCodesTable();
          await _createRevokedTokensTable();
          await _createOAuthClientsTable();
          await createValueIndexes();
        },
        // fhir_r4_db runs ANALYZE from its own beforeOpen when the database
        // has no planner statistics. Overriding `migration` replaces that
        // beforeOpen wholesale, so it is wired here again; without it the
        // planner guessed, and on a 5 GB database chose the primary key for
        // a reference lookup whose leading column matched 2.9 million rows.
        beforeOpen: ensurePlannerStatistics,
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await _createUsersTable();
          }
          if (from < 3) {
            await _createExportJobsTable();
          }
          if (from < 4) {
            await customStatement(
              'ALTER TABLE export_jobs ADD COLUMN group_id TEXT',
            );
          }
          if (from < 5) {
            await customStatement(
              'ALTER TABLE export_jobs ADD COLUMN type_filters TEXT',
            );
          }
          if (from < 6) {
            await customStatement('ALTER TABLE users ADD COLUMN scopes TEXT');
          }
          if (from < 7) {
            // FhirDb tables that didn't exist in schema version ≤6
            await m.createTable(syncResources);
            await m.createTable(canonicalResources);
            await m.createTable(generalStorage);
            await createValueIndexes();
          }
          if (from < 8) {
            await _createAuthorizationCodesTable();
          }
          if (from < 9) {
            await _createRevokedTokensTable();
          }
          if (from < 10) {
            await customStatement(
              'ALTER TABLE users ADD COLUMN failed_login_count '
              'INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE users ADD COLUMN locked_until INTEGER',
            );
          }
          if (from < 11) {
            // Make referenceValue nullable for identifier-only references
            await customStatement(
              'CREATE TABLE reference_search_parameters_new ( '
              'resource_type TEXT NOT NULL, '
              'id TEXT NOT NULL, '
              'last_updated INTEGER NOT NULL, '
              'search_path TEXT NOT NULL, '
              "search_name TEXT NOT NULL DEFAULT '', "
              'param_index INTEGER NOT NULL, '
              'reference_value TEXT, '
              'reference_resource_type TEXT, '
              'reference_id_part TEXT, '
              'reference_version TEXT, '
              'reference_base_url TEXT, '
              'identifier_system TEXT, '
              'identifier_value TEXT, '
              'PRIMARY KEY (resource_type, id, search_path, param_index) '
              ')',
            );
            await customStatement(
              'INSERT INTO reference_search_parameters_new '
              'SELECT * FROM reference_search_parameters',
            );
            await customStatement(
              'DROP TABLE reference_search_parameters',
            );
            await customStatement(
              'ALTER TABLE reference_search_parameters_new '
              'RENAME TO reference_search_parameters',
            );
          }
          if (from < 12) {
            // Add versionId column to resources_history with new primary key.
            await customStatement(
              'CREATE TABLE resources_history_new ( '
              'resource_type TEXT NOT NULL, '
              'id TEXT NOT NULL, '
              'version_id TEXT NOT NULL, '
              'resource TEXT NOT NULL, '
              'last_updated INTEGER NOT NULL, '
              'PRIMARY KEY (resource_type, id, version_id) '
              ')',
            );
            await customStatement(
              'INSERT OR IGNORE INTO resources_history_new '
              '(resource_type, id, version_id, resource, last_updated) '
              'SELECT resource_type, id, '
              'COALESCE('
              r"json_extract(resource, '$.meta.versionId'), "
              'CAST(last_updated AS TEXT) '
              '), '
              'resource, last_updated '
              'FROM resources_history',
            );
            await customStatement('DROP TABLE resources_history');
            await customStatement(
              'ALTER TABLE resources_history_new '
              'RENAME TO resources_history',
            );
          }
          if (from < 13) {
            // Convert lastUpdated from seconds to milliseconds.
            const tables = [
              'resources',
              'resources_history',
              'string_search_parameters',
              'token_search_parameters',
              'reference_search_parameters',
              'date_search_parameters',
              'number_search_parameters',
              'quantity_search_parameters',
              'uri_search_parameters',
              'composite_search_parameters',
              'special_search_parameters',
              'sync_resources',
            ];
            for (final table in tables) {
              await customStatement(
                'UPDATE $table SET last_updated = last_updated * 1000',
              );
            }
          }
          if (from < 14) {
            // fhir_r4_db schema 7: the search index is derived data and its
            // extraction changed under this version (dates as [low, high)
            // ranges at their own precision, Period and Timing indexed,
            // quantities with low/high, exact and normalized string values,
            // contained resources under `#Type`, composites, `near`). Every
            // row is re-extracted from the stored resources; the value
            // indexes and planner statistics are rebuilt at the end. Paged,
            // so the 5 GB MIMIC load takes 467s and bounded memory.
            // Re-extracted below, once, by the schema-18 step.
          }
          if (from < 15) {
            // fhir_r4_db schema 8: partial indexes on id for contained rows,
            // so re-saving a container deletes its contained rows through an
            // index instead of scanning every index table (measured 4× on
            // the save path, fhir_r4_db 2026-09-06). Created below by the
            // schema-18 rebuild, on the tables in their current shape.
          }
          if (from < 16) {
            // The patient an account is about, set by an administrator at
            // registration. The SERVER puts it in the token's `patient`
            // claim; until this column existed the login body did, so any
            // caller with patient/ scopes chose its own compartment
            // (REVIEW-2026-09-06 finding 6).
            // Guarded: a database created at the current schema and stamped
            // back (the upgrade tests do this) already has the column, and
            // ALTER TABLE ADD COLUMN on an existing column is an error.
            final columns =
                await customSelect('PRAGMA table_info(users)').get();
            if (!columns.any((c) => c.read<String>('name') == 'patient_id')) {
              await customStatement(
                'ALTER TABLE users ADD COLUMN patient_id TEXT',
              );
            }
            // The redirect_uri first seen for each OAuth client_id, so a
            // later authorize request naming the same client and a different
            // redirect is refused (finding 10: there was no client registry,
            // so an authorization code could be sent anywhere).
            await _createOAuthClientsTable();
          }
          if (from < 17) {
            // fhir_r4_db schema 9: Address and ContactPoint string rows
            // moved onto the whole-value param_index convention `_sort`
            // relies on, so the search index is re-extracted from the
            // stored resources (derived data, as the schema-14 step did).
            // Re-extracted below, once, by the schema-18 step.
          }
          if (from < 18) {
            // fhir_r4_db schema 10 (REVIEW-2026-09-06 §4): the index tables
            // lose search_path and their five-column key, the single-column
            // value indexes give way to covering composites, and resources
            // gains (resource_type, last_updated). The tables are dropped
            // and re-extracted in the new shape; this one rebuild also
            // serves the 14 and 17 steps.
            await dropLegacyValueIndexes();
            await rebuildSearchIndex();
          }
        },
      );

  // ──────────────────────────────────────────────────────────────────────────
  // Schema creation helpers
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _createUsersTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE CHECK(length(username) >= 3 AND length(username) <= 100),
        password_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'clinician',
        active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        last_login INTEGER,
        scopes TEXT,
        failed_login_count INTEGER NOT NULL DEFAULT 0,
        locked_until INTEGER,
        patient_id TEXT
      )
    ''');
  }

  /// One row per OAuth client_id this server has issued a code to, pinning
  /// the redirect_uri it first authorized with. Trust on first use: fhirant
  /// has no dynamic client registration, and without a pin a crafted
  /// authorize link could send a real user's authorization code to any URL.
  Future<void> _createOAuthClientsTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS oauth_clients (
        client_id TEXT NOT NULL PRIMARY KEY,
        redirect_uri TEXT NOT NULL,
        first_seen INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');
  }

  Future<void> _createExportJobsTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS export_jobs (
        job_id TEXT NOT NULL PRIMARY KEY,
        status TEXT NOT NULL DEFAULT 'pending',
        request_url TEXT NOT NULL,
        transaction_time INTEGER NOT NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        completed_at INTEGER,
        output_json TEXT,
        error_json TEXT,
        resource_types TEXT,
        since INTEGER,
        export_level TEXT NOT NULL,
        patient_id TEXT,
        group_id TEXT,
        type_filters TEXT,
        requested_by TEXT
      )
    ''');
  }

  Future<void> _createLogsTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        level TEXT NOT NULL CHECK(length(level) >= 4 AND length(level) <= 10),
        message TEXT NOT NULL,
        method TEXT,
        url TEXT,
        status_code INTEGER,
        response_time INTEGER,
        client_ip TEXT,
        "user" TEXT,
        stack_trace TEXT,
        timestamp INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');
  }

  Future<void> _createAuthorizationCodesTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS authorization_codes (
        code TEXT NOT NULL PRIMARY KEY,
        client_id TEXT NOT NULL,
        user_id INTEGER NOT NULL,
        redirect_uri TEXT NOT NULL,
        scope TEXT NOT NULL DEFAULT '',
        code_challenge TEXT,
        code_challenge_method TEXT,
        expires_at INTEGER NOT NULL,
        used INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');
  }

  Future<void> _createRevokedTokensTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS revoked_tokens (
        token_hash TEXT NOT NULL PRIMARY KEY,
        revoked_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL
      )
    ''');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Backup: the whole database as one passphrase-encrypted SQLite file
  // ──────────────────────────────────────────────────────────────────────────

  /// The cipher scheme every FHIRant database and backup is written with.
  static const cipherScheme = 'sqlcipher';

  /// Writes every table of this database to [path] as a SQLite file
  /// encrypted under [passphrase], streamed by SQLite: `ATTACH … KEY` then
  /// `INSERT INTO bk.t SELECT * FROM main.t` per table, `user_version`
  /// carried across. No indexes: they are derived, [restoreEncrypted] reads
  /// the tables and never the indexes, and building them was half the time
  /// and all the memory (measured 2026-09-07 on the 6.98 GB MIMIC store:
  /// the table copies held 226 MB resident throughout, the index builds
  /// took the process to 707 MB and the file to 6.98 GB; without them the
  /// whole store is written in 41 s as a 4.08 GB file). A backup opened
  /// directly as a database gets its indexes from [createValueIndexes].
  ///
  /// This is the device-to-device path. The database is encrypted at rest
  /// under a key sealed in platform secure storage, which cannot travel; a
  /// passphrase is the only thing a replacement device can hold. The key is
  /// derived by the cipher (SQLCipher-4 scheme, PBKDF2-HMAC-SHA512 with its
  /// default iteration count) and the file opens as a database with it.
  ///
  /// The Bundle-in-JSON export this replaces was measured at 51.8 s and
  /// 548 MB of memory per 50 MB of resources (REVIEW-2026-09-06 finding
  /// 33), which does not reach a real store's size at all. `VACUUM INTO`
  /// was tried first: under sqlite3mc the copy keeps the SOURCE key, which
  /// is the point of not using it.
  ///
  /// [path] must not exist. [passphrase] must not be empty.
  Future<void> copyEncrypted(String path, String passphrase) async {
    if (passphrase.isEmpty) {
      throw ArgumentError.value(passphrase, 'passphrase', 'must not be empty');
    }
    if (File(path).existsSync()) {
      throw ArgumentError.value(path, 'path', 'already exists');
    }
    await _requireCipher();
    await customStatement(
      "ATTACH DATABASE '${_sqlLiteral(path)}' AS bk "
      "KEY '${_sqlLiteral(passphrase)}'",
    );
    try {
      final objects = await customSelect(
        "SELECT name, sql FROM main.sqlite_master WHERE type = 'table' "
        "AND sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY name",
      ).get();
      for (final o in objects) {
        final name = o.read<String>('name');
        await customStatement(_schemaIn('bk', name, o.read<String>('sql')));
        await customStatement(
          'INSERT INTO bk."$name" SELECT * FROM main."$name"',
        );
      }
      final version =
          await customSelect('PRAGMA main.user_version').getSingle();
      await customStatement(
        'PRAGMA bk.user_version = ${version.data.values.first}',
      );
    } finally {
      await customStatement('DETACH DATABASE bk');
    }
  }

  /// Merges the backup at [path], written by [copyEncrypted] under
  /// [passphrase], into this database.
  ///
  /// The backup's resources win: `resources` rows replace, history merges,
  /// the index rows of every restored resource (and of what it contained)
  /// are replaced by the backup's. Everything else (accounts, OAuth client
  /// pins, revoked tokens, export jobs, logs, sync and canonical stores) is
  /// merged with the local rows winning on a key clash, so restoring onto a
  /// device that already has accounts keeps them. On a replacement device
  /// every table is empty and the result is the backup, byte for byte.
  ///
  /// A backup written by an older schema is upgraded first, in place, by
  /// opening it as a [FhirAntDb]; one from a newer schema is refused
  /// ([BackupSchemaTooNew]). A wrong passphrase, or a file that is not a
  /// backup, is [BackupUnreadable]. Returns the number of resources
  /// restored.
  Future<int> restoreEncrypted(String path, String passphrase) async {
    if (passphrase.isEmpty) {
      throw ArgumentError.value(passphrase, 'passphrase', 'must not be empty');
    }
    if (!File(path).existsSync()) {
      throw ArgumentError.value(path, 'path', 'does not exist');
    }
    await _requireCipher();
    // The passphrase and the schema version, read raw: drift stamps its own
    // version on open, so a newer backup would look current by then.
    final int version;
    try {
      final raw = sqlite3.open(path)
        ..execute("PRAGMA cipher = '$cipherScheme'")
        ..execute("PRAGMA key = '${_sqlLiteral(passphrase)}'");
      try {
        version = raw.select('PRAGMA user_version').first.values.first! as int;
      } finally {
        raw.close();
      }
    } catch (e) {
      throw BackupUnreadable('$e');
    }
    if (version > schemaVersion) {
      throw BackupSchemaTooNew(version, schemaVersion);
    }
    if (version < schemaVersion) {
      // Upgrade the backup to this schema, in place, before merging it.
      final backup = FhirAntDb(
        NativeDatabase(
          File(path),
          setup: (raw) {
            raw
              ..execute("PRAGMA cipher = '$cipherScheme'")
              ..execute("PRAGMA key = '${_sqlLiteral(passphrase)}'");
          },
        ),
      );
      try {
        await backup.customSelect('PRAGMA user_version').getSingle();
      } finally {
        await backup.close();
      }
    }

    await customStatement(
      "ATTACH DATABASE '${_sqlLiteral(path)}' AS bk "
      "KEY '${_sqlLiteral(passphrase)}'",
    );
    try {
      final tables = (await customSelect(
        "SELECT name FROM main.sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%'",
      ).get())
          .map((r) => r.read<String>('name'))
          .toSet();
      final backupTables = (await customSelect(
        "SELECT name FROM bk.sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%'",
      ).get())
          .map((r) => r.read<String>('name'))
          .toSet();
      const searchTables = FhirDb.searchTableNames;
      final restored = await transaction(() async {
        // The restored resources' own index rows, and those of anything
        // they contain, go; the backup's come in their place.
        for (final table in searchTables) {
          if (!backupTables.contains(table)) continue;
          await customStatement(
            'DELETE FROM main."$table" WHERE (resource_type, id) IN '
            '(SELECT resource_type, id FROM bk.resources)',
          );
          await customStatement(
            'DELETE FROM main."$table" WHERE rowid IN ( '
            'SELECT x.rowid FROM main."$table" x JOIN bk.resources r '
            "ON x.id >= r.resource_type || '/' || r.id || '#' "
            r"AND x.id < r.resource_type || '/' || r.id || '$' "
            "WHERE x.resource_type LIKE '#%')",
          );
          await customStatement(
            'INSERT INTO main."$table" SELECT * FROM bk."$table"',
          );
        }
        await customStatement(
          'INSERT OR REPLACE INTO main.resources SELECT * FROM bk.resources',
        );
        for (final table in tables) {
          if (table == 'resources' ||
              searchTables.contains(table) ||
              !backupTables.contains(table)) {
            continue;
          }
          await customStatement(
            'INSERT OR IGNORE INTO main."$table" SELECT * FROM bk."$table"',
          );
        }
        final n = await customSelect('SELECT count(*) AS c FROM bk.resources')
            .getSingle();
        return n.read<int>('c');
      });
      await customStatement('ANALYZE');
      return restored;
    } finally {
      await customStatement('DETACH DATABASE bk');
    }
  }

  /// Refuses to go on when this SQLite build has no cipher.
  ///
  /// On plain SQLite `PRAGMA cipher`, `PRAGMA key` and `ATTACH … KEY` parse
  /// and do nothing, so a backup would be written in the clear and reported
  /// as encrypted. The server and the app are built on sqlite3mc (the build
  /// hook in their pubspecs); this package's own tests are not, which is
  /// where this was found. sqlite3mc answers `PRAGMA cipher` with the scheme;
  /// plain SQLite answers with no row.
  Future<void> _requireCipher() async {
    await customStatement("PRAGMA cipher = '$cipherScheme'");
    final rows = await customSelect('PRAGMA cipher').get();
    if (rows.isEmpty) {
      throw const NoCipherInThisBuild();
    }
  }

  /// A CREATE TABLE / CREATE INDEX statement from `sqlite_master`, rewritten
  /// to create the same object in schema [schema]. Only the object's own
  /// name moves; an index's `ON table` stays bare, which SQLite resolves in
  /// the index's schema.
  static String _schemaIn(String schema, String name, String sql) {
    final escaped = RegExp.escape(name);
    final table = RegExp('^CREATE TABLE\\s+(IF NOT EXISTS\\s+)?"?$escaped"?');
    if (table.hasMatch(sql)) {
      return sql.replaceFirst(table, 'CREATE TABLE $schema."$name"');
    }
    final index = RegExp(
      '^CREATE (UNIQUE )?INDEX\\s+(IF NOT EXISTS\\s+)?"?$escaped"?',
    );
    if (index.hasMatch(sql)) {
      return sql.replaceFirstMapped(
        index,
        (m) => 'CREATE ${m.group(1) ?? ''}INDEX $schema."$name"',
      );
    }
    throw StateError('unexpected schema object: $sql');
  }

  static String _sqlLiteral(String value) => value.replaceAll("'", "''");

  // ──────────────────────────────────────────────────────────────────────────
  // FHIR Delegation — maintain existing API surface
  // ──────────────────────────────────────────────────────────────────────────

  Future<fhir.Resource?> getResource(
    fhir.R4ResourceType resourceType,
    String id,
  ) =>
      fhirDao.getResource(resourceType, id);

  /// Saves [resource] and returns it as stored (server-assigned version and
  /// lastUpdated), or null when the save failed. Callers used to get a bool
  /// and re-read the resource to learn its version (REVIEW-2026-09-06
  /// finding 32). A [VersionConflict] from [ifMatchVersion] (HTTP `If-Match`)
  /// is rethrown: it is the caller's 412, not a failure.
  Future<fhir.Resource?> saveResource(
    fhir.Resource resource, {
    String? ifMatchVersion,
    bool mergeTags = true,
  }) async {
    try {
      return await fhirDao.saveResource(
        resource,
        ifMatchVersion: ifMatchVersion,
        mergeTags: mergeTags,
      );
    } on VersionConflict {
      rethrow;
    } catch (e) {
      stderr.writeln('Error in saveResource: $e');
      return null;
    }
  }

  Future<bool> saveResources(List<fhir.Resource> resourcesList) =>
      fhirDao.saveResources(resourcesList);

  /// The patient this resource is about, or null when it names none.
  ///
  /// Inherited from `FhirDao` since fhir_r4_db 0.9.0. `FhirDb` delegates
  /// nothing, so the wrapper stays, like every other method on this class.
  Future<String?> subjectOfCare(String resourceType, String id) =>
      fhirDao.subjectOfCare(resourceType, id);

  Future<bool> deleteResource(
    fhir.R4ResourceType resourceType,
    String id, {
    String? ifMatchVersion,
  }) =>
      fhirDao.deleteResource(resourceType, id, ifMatchVersion: ifMatchVersion);

  Future<List<fhir.Resource>> getResourcesWithPagination({
    required fhir.R4ResourceType resourceType,
    required int count,
    required int offset,
  }) =>
      fhirDao.getResourcesWithPagination(
        resourceType: resourceType,
        count: count,
        offset: offset,
      );

  Future<List<fhir.Resource>> getResourcesByType(
    fhir.R4ResourceType resourceType,
  ) =>
      fhirDao.getResourcesByType(resourceType);

  Future<int> getResourceCount(fhir.R4ResourceType resourceType) =>
      fhirDao.getResourceCount(resourceType);

  Future<List<fhir.R4ResourceType>> getResourceTypes() =>
      fhirDao.getResourceTypes();

  /// The versions of one resource that are resources (no tombstone).
  Future<List<fhir.Resource>> getResourceHistory(
    fhir.R4ResourceType resourceType,
    String id,
  ) =>
      fhirDao.getResourceHistory(resourceType, id);

  /// Every version of one resource, newest first, a delete as a tombstone
  /// entry; `_since`, `_at` and the page as on the DAO.
  Future<List<HistoryEntry>> getHistory(
    fhir.R4ResourceType resourceType,
    String id, {
    DateTime? since,
    DateTime? at,
    int? count,
    int? offset,
  }) =>
      fhirDao.getHistory(
        resourceType,
        id,
        since: since,
        at: at,
        count: count,
        offset: offset,
      );

  /// The total [getHistory] pages over.
  Future<int> countHistory(
    fhir.R4ResourceType resourceType,
    String id, {
    DateTime? since,
    DateTime? at,
  }) =>
      fhirDao.countHistory(resourceType, id, since: since, at: at);

  /// One version by its key, or null; see [FhirDao.getVersion].
  Future<HistoryEntry?> getVersion(
    fhir.R4ResourceType resourceType,
    String id,
    String versionId,
  ) =>
      fhirDao.getVersion(resourceType, id, versionId);

  /// Every version of every resource of one type, newest first, one page
  /// (REVIEW-2026-09-06 finding 36: the whole table was read and parsed per
  /// request and paged in Dart). `_at` is the version current at that
  /// instant per resource; `_since` the versions written after it.
  Future<List<HistoryEntry>> getTypeHistory(
    fhir.R4ResourceType resourceType, {
    DateTime? since,
    DateTime? at,
    int? count,
    int? offset,
  }) =>
      _historyPage(
        resourceType: resourceType.toString(),
        since: since,
        at: at,
        count: count,
        offset: offset,
      );

  /// The total [getTypeHistory] pages over.
  Future<int> countTypeHistory(
    fhir.R4ResourceType resourceType, {
    DateTime? since,
    DateTime? at,
  }) =>
      _historyCount(
        resourceType: resourceType.toString(),
        since: since,
        at: at,
      );

  /// Every version of every resource, newest first, one page.
  Future<List<HistoryEntry>> getSystemHistory({
    DateTime? since,
    DateTime? at,
    int? count,
    int? offset,
  }) =>
      _historyPage(since: since, at: at, count: count, offset: offset);

  /// The total [getSystemHistory] pages over.
  Future<int> countSystemHistory({DateTime? since, DateTime? at}) =>
      _historyCount(since: since, at: at);

  /// The rows of type or system history as SQL: `_at` is a join to the
  /// latest `last_updated` per resource at or before that instant, `_since`
  /// a range; the page is `LIMIT/OFFSET` on the ordered rows, and the count
  /// is `count(*)` over the same rows. Both go through
  /// `(resource_type, last_updated)` on `resources_history`.
  String _historySql({
    required String select,
    required String? resourceType,
    required DateTime? since,
    required DateTime? at,
  }) {
    final typeWhere = resourceType == null ? '' : 'resource_type = ? AND ';
    if (at != null) {
      return 'SELECT $select FROM resources_history rh INNER JOIN ( '
          'SELECT resource_type, id, MAX(last_updated) AS max_lu '
          'FROM resources_history WHERE ${typeWhere}last_updated <= ? '
          'GROUP BY resource_type, id) sub '
          'ON rh.resource_type = sub.resource_type AND rh.id = sub.id '
          'AND rh.last_updated = sub.max_lu';
    }
    final sinceWhere = since == null ? '' : 'last_updated > ? ';
    final where = '$typeWhere$sinceWhere'.trim();
    final cut =
        where.endsWith('AND') ? where.substring(0, where.length - 3) : where;
    return 'SELECT $select FROM resources_history rh'
        '${cut.trim().isEmpty ? '' : ' WHERE ${cut.trim()}'}';
  }

  List<Variable<Object>> _historyVariables({
    required String? resourceType,
    required DateTime? since,
    required DateTime? at,
  }) =>
      [
        if (resourceType != null) Variable.withString(resourceType),
        if (at != null)
          Variable.withInt(at.millisecondsSinceEpoch)
        else if (since != null)
          Variable.withInt(since.millisecondsSinceEpoch),
      ];

  Future<List<HistoryEntry>> _historyPage({
    String? resourceType,
    DateTime? since,
    DateTime? at,
    int? count,
    int? offset,
  }) async {
    var sql = _historySql(
      select: 'rh.*',
      resourceType: resourceType,
      since: since,
      at: at,
    );
    sql += ' ORDER BY rh.last_updated DESC, rh.version_id DESC';
    if (count != null) {
      sql += ' LIMIT $count OFFSET ${offset ?? 0}';
    } else if (offset != null && offset > 0) {
      sql += ' LIMIT -1 OFFSET $offset';
    }
    final rows = await customSelect(
      sql,
      variables: _historyVariables(
        resourceType: resourceType,
        since: since,
        at: at,
      ),
      readsFrom: {resourcesHistory},
    ).get();
    return [
      for (final row in rows)
        HistoryEntry.fromRow(resourcesHistory.map(row.data)),
    ];
  }

  Future<int> _historyCount({
    String? resourceType,
    DateTime? since,
    DateTime? at,
  }) async {
    final row = await customSelect(
      _historySql(
        select: 'count(*) AS c',
        resourceType: resourceType,
        since: since,
        at: at,
      ),
      variables: _historyVariables(
        resourceType: resourceType,
        since: since,
        at: at,
      ),
      readsFrom: {resourcesHistory},
    ).getSingle();
    return row.read<int>('c');
  }

  Future<List<fhir.Resource>> search({
    required fhir.R4ResourceType resourceType,
    Map<String, List<String>>? searchParameters,
    List<HasParameter>? hasParameters,
    int? count,
    int? offset,
    List<String>? sort,
    CompartmentScope? compartment,
  }) =>
      fhirDao.search(
        resourceType: resourceType,
        searchParameters: searchParameters,
        hasParameters: hasParameters,
        count: count,
        offset: offset,
        sort: sort,
        compartment: compartment,
      );

  Future<int> searchCount({
    required fhir.R4ResourceType resourceType,
    Map<String, List<String>>? searchParameters,
    List<HasParameter>? hasParameters,
    CompartmentScope? compartment,
  }) =>
      fhirDao.searchCount(
        resourceType: resourceType,
        searchParameters: searchParameters,
        hasParameters: hasParameters,
        compartment: compartment,
      );

  /// The `(type, id)` targets of a reference search parameter on the given
  /// resources, for `_include`. See `FhirDao.referenceTargets`.
  Future<Set<(String, String)>> referenceTargets(
    String resourceType,
    Iterable<String> ids, {
    String? parameter,
    String? targetType,
  }) =>
      fhirDao.referenceTargets(
        resourceType,
        ids,
        parameter: parameter,
        targetType: targetType,
      );

  /// Refreshes planner statistics where the data has outgrown them. See
  /// `FhirDb.optimizePlannerStatistics`; the server calls it hourly and on
  /// stop.
  Future<void> optimizeStatistics() => optimizePlannerStatistics();

  /// Every resource in [scope]'s compartment, by type. See
  /// `FhirDao.compartmentMembers`.
  Future<Map<String, Set<String>>> compartmentMembers(
    CompartmentScope scope, {
    Iterable<String>? types,
    DateTime? since,
  }) =>
      fhirDao.compartmentMembers(scope, types: types, since: since);

  // ──────────────────────────────────────────────────────────────────────────
  // Server-specific: export
  // ──────────────────────────────────────────────────────────────────────────

  /// The stored JSON of every current [resourceType] resource, one string
  /// per resource, in pages of [pageSize] rows read by keyset on the
  /// `(resource_type, last_updated)` index with rowid as the tie-break
  /// (`(last_updated, rowid) > (?, ?) ORDER BY last_updated, rowid LIMIT n`),
  /// so an export of any size holds one page at a time and never decodes a
  /// resource: the text is what `saveResource` stored and is written out as
  /// it is.
  ///
  /// Measured on the 929k MIMIC copy (2026-09-08, plain sqlite3): a rowid
  /// keyset with `resource_type = ?` made the planner take the type index
  /// and sort every Observation rowid PER PAGE (2.8 s per 10k rows); forcing
  /// the rowid scan reads the whole table for a small type (Condition, 5k
  /// rows: 1.3 s). This keyset walks the index in order for both: 100k
  /// Observations in 366 ms, 5k Conditions in 13 ms.
  ///
  /// [since] keeps resources with `last_updated >= since`. [ids] restricts
  /// to those ids, read in `IN (...)` chunks of [pageSize]. Row order is
  /// last-updated order, or id order when [ids] is given.
  ///
  /// REVIEW-2026-09-06 finding 34: `$export` used to read a whole type into
  /// a `List<Resource>` (decode, then re-encode every one) before writing.
  Stream<String> exportJson(
    fhir.R4ResourceType resourceType, {
    DateTime? since,
    Iterable<String>? ids,
    int pageSize = 500,
  }) async* {
    final type = resourceType.toString();
    final sinceMs = since?.millisecondsSinceEpoch;
    if (ids != null) {
      final sorted = ids.toList()..sort();
      for (var i = 0; i < sorted.length; i += pageSize) {
        final chunk = sorted.sublist(
          i,
          i + pageSize > sorted.length ? sorted.length : i + pageSize,
        );
        final marks = List.filled(chunk.length, '?').join(', ');
        final rows = await customSelect(
          'SELECT resource FROM resources WHERE resource_type = ? '
          'AND id IN ($marks)'
          '${sinceMs == null ? '' : ' AND last_updated >= ?'} ORDER BY id',
          variables: [
            Variable.withString(type),
            for (final id in chunk) Variable.withString(id),
            if (sinceMs != null) Variable.withInt(sinceMs),
          ],
          readsFrom: {resources},
        ).get();
        for (final row in rows) {
          yield row.read<String>('resource');
        }
      }
      return;
    }
    var lastUpdated = -1;
    var lastRowid = -1;
    while (true) {
      final rows = await customSelect(
        'SELECT last_updated AS lu, rowid AS rid, resource FROM resources '
        'WHERE resource_type = ? '
        '${sinceMs == null ? '' : 'AND last_updated >= ? '}'
        'AND (last_updated, rowid) > (?, ?) '
        'ORDER BY last_updated, rowid LIMIT ?',
        variables: [
          Variable.withString(type),
          if (sinceMs != null) Variable.withInt(sinceMs),
          Variable.withInt(lastUpdated),
          Variable.withInt(lastRowid),
          Variable.withInt(pageSize),
        ],
        readsFrom: {resources},
      ).get();
      if (rows.isEmpty) return;
      for (final row in rows) {
        lastUpdated = row.read<int>('lu');
        lastRowid = row.read<int>('rid');
        yield row.read<String>('resource');
      }
      if (rows.length < pageSize) return;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Server-specific: getResourcesByTypeSince
  // ──────────────────────────────────────────────────────────────────────────

  Future<List<fhir.Resource>> getResourcesByTypeSince(
    fhir.R4ResourceType resourceType, {
    DateTime? since,
  }) async {
    final resourceTypeString = resourceType.toString();
    final query = select(resources)
      ..where((tbl) {
        final typeCond = tbl.resourceType.equals(resourceTypeString);
        if (since != null) {
          return typeCond &
              tbl.lastUpdated
                  .isBiggerOrEqualValue(since.millisecondsSinceEpoch);
        }
        return typeCond;
      })
      ..orderBy([(tbl) => OrderingTerm.asc(tbl.lastUpdated)]);
    final rows = await query.get();
    return rows
        .map((row) => fhir.Resource.fromJsonString(row.resource))
        .toList();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // User management methods
  // ──────────────────────────────────────────────────────────────────────────

  Future<int> getUserCount() async {
    final rows = await customSelect('SELECT COUNT(*) AS c FROM users').get();
    return rows.first.read<int>('c');
  }

  Future<User?> getUserByUsername(String username) async {
    final rows = await customSelect(
      'SELECT * FROM users WHERE username = ?',
      variables: [Variable.withString(username)],
    ).get();
    if (rows.isEmpty) return null;
    return User.fromRow(rows.first);
  }

  Future<User?> getUserById(int id) async {
    final rows = await customSelect(
      'SELECT * FROM users WHERE id = ?',
      variables: [Variable.withInt(id)],
    ).get();
    if (rows.isEmpty) return null;
    return User.fromRow(rows.first);
  }

  Future<int> createUser({
    required String username,
    required String passwordHash,
    required String salt,
    String role = 'clinician',
    String? scopes,
    String? patientId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await customStatement(
      'INSERT INTO users '
      '(username, password_hash, salt, role, active, created_at, scopes, '
      'patient_id) '
      'VALUES (?, ?, ?, ?, 1, ?, ?, ?)',
      [username, passwordHash, salt, role, now, scopes, patientId],
    );
    final rows = await customSelect('SELECT last_insert_rowid() AS id').get();
    return rows.first.read<int>('id');
  }

  Future<void> updateLastLogin(int id) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await customStatement(
      'UPDATE users SET last_login = ? WHERE id = ?',
      [now, id],
    );
  }

  /// Replaces a user's stored password hash and salt. Used to transparently
  /// upgrade a legacy/low-cost hash to the current KDF on a successful login.
  Future<void> updatePassword(int id, String passwordHash, String salt) async {
    await customStatement(
      'UPDATE users SET password_hash = ?, salt = ? WHERE id = ?',
      [passwordHash, salt, id],
    );
  }

  Future<void> deactivateUser(int id) async {
    await customStatement(
      'UPDATE users SET active = 0 WHERE id = ?',
      [id],
    );
  }

  Future<List<User>> getAllUsers() async {
    final rows = await customSelect('SELECT * FROM users').get();
    return rows.map(User.fromRow).toList();
  }

  /// Increment the failed login counter for a user and return the new count.
  Future<int> incrementFailedLogins(int id) async {
    await customStatement(
      'UPDATE users SET failed_login_count = failed_login_count + 1 '
      'WHERE id = ?',
      [id],
    );
    final rows = await customSelect(
      'SELECT failed_login_count FROM users WHERE id = ?',
      variables: [Variable.withInt(id)],
    ).get();
    return rows.first.read<int>('failed_login_count');
  }

  /// Reset the failed login counter and clear any lockout for a user.
  Future<void> resetFailedLogins(int id) async {
    await customStatement(
      'UPDATE users SET failed_login_count = 0, locked_until = NULL '
      'WHERE id = ?',
      [id],
    );
  }

  /// Lock an account until the given time.
  Future<void> lockAccount(int id, DateTime until) async {
    final untilEpoch = until.millisecondsSinceEpoch ~/ 1000;
    await customStatement(
      'UPDATE users SET locked_until = ? WHERE id = ?',
      [untilEpoch, id],
    );
  }

  /// Unlock an account (admin action). Alias for [resetFailedLogins].
  Future<void> unlockAccount(int id) => resetFailedLogins(id);

  /// Sets (or clears, with null) the Patient this account is about. Its id
  /// goes into the token's `patient` claim and confines patient/ scopes.
  Future<void> setUserPatient(int id, String? patientId) async {
    await customStatement(
      'UPDATE users SET patient_id = ? WHERE id = ?',
      [patientId, id],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // OAuth client redirect pins
  // ──────────────────────────────────────────────────────────────────────────

  /// The redirect_uri pinned for [clientId], or null when the client has
  /// never been issued a code.
  Future<String?> getOAuthClientRedirect(String clientId) async {
    final rows = await customSelect(
      'SELECT redirect_uri FROM oauth_clients WHERE client_id = ?',
      variables: [Variable.withString(clientId)],
    ).get();
    if (rows.isEmpty) return null;
    return rows.first.read<String>('redirect_uri');
  }

  /// Pins [redirectUri] for [clientId]; a second call for the same client is
  /// ignored, the first pin stands.
  Future<void> registerOAuthClient(String clientId, String redirectUri) async {
    await customStatement(
      'INSERT OR IGNORE INTO oauth_clients (client_id, redirect_uri) '
      'VALUES (?, ?)',
      [clientId, redirectUri],
    );
  }

  /// Removes the pin for [clientId] (an administrator re-registering a
  /// client whose redirect changed).
  Future<void> deleteOAuthClient(String clientId) async {
    await customStatement(
      'DELETE FROM oauth_clients WHERE client_id = ?',
      [clientId],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Authorization code management methods
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> createAuthorizationCode({
    required String code,
    required String clientId,
    required int userId,
    required String redirectUri,
    required String scope,
    String? codeChallenge,
    String? codeChallengeMethod,
    required DateTime expiresAt,
  }) async {
    final expiresAtEpoch = expiresAt.millisecondsSinceEpoch ~/ 1000;
    await customStatement(
      'INSERT INTO authorization_codes '
      '(code, client_id, user_id, redirect_uri, scope, code_challenge, '
      'code_challenge_method, expires_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        code,
        clientId,
        userId,
        redirectUri,
        scope,
        codeChallenge,
        codeChallengeMethod,
        expiresAtEpoch,
      ],
    );
  }

  Future<AuthorizationCode?> getAuthorizationCode(String code) async {
    final rows = await customSelect(
      'SELECT * FROM authorization_codes WHERE code = ?',
      variables: [Variable.withString(code)],
    ).get();
    if (rows.isEmpty) return null;
    return AuthorizationCode.fromRow(rows.first);
  }

  Future<void> markAuthorizationCodeUsed(String code) async {
    await customStatement(
      'UPDATE authorization_codes SET used = 1 WHERE code = ?',
      [code],
    );
  }

  /// Delete expired or used authorization codes (cleanup).
  Future<void> cleanupAuthorizationCodes() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await customStatement(
      'DELETE FROM authorization_codes WHERE used = 1 OR expires_at < ?',
      [now],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Revoked token management methods
  // ──────────────────────────────────────────────────────────────────────────

  /// Store a revoked token hash with its expiration time.
  Future<void> revokeToken(String tokenHash, DateTime expiresAt) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expiresAtEpoch = expiresAt.millisecondsSinceEpoch ~/ 1000;
    await customStatement(
      'INSERT OR IGNORE INTO revoked_tokens '
      '(token_hash, revoked_at, expires_at) VALUES (?, ?, ?)',
      [tokenHash, now, expiresAtEpoch],
    );
  }

  /// Check whether a token hash has been revoked.
  Future<bool> isTokenRevoked(String tokenHash) async {
    final rows = await customSelect(
      'SELECT 1 FROM revoked_tokens WHERE token_hash = ?',
      variables: [Variable.withString(tokenHash)],
    ).get();
    return rows.isNotEmpty;
  }

  /// Delete expired revoked-token entries (garbage collection).
  Future<void> cleanupRevokedTokens() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await customStatement(
      'DELETE FROM revoked_tokens WHERE expires_at < ?',
      [now],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Export job management methods
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> createExportJob({
    required String jobId,
    required String status,
    required String requestUrl,
    required DateTime transactionTime,
    String? resourceTypes,
    DateTime? since,
    required String exportLevel,
    String? patientId,
    String? groupId,
    String? typeFilters,
    String? requestedBy,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final txTime = transactionTime.millisecondsSinceEpoch ~/ 1000;
    final sinceTime =
        since != null ? since.millisecondsSinceEpoch ~/ 1000 : null;
    await customStatement(
      'INSERT INTO export_jobs (job_id, status, request_url, transaction_time, '
      'created_at, resource_types, since, export_level, patient_id, group_id, '
      'type_filters, requested_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        jobId,
        status,
        requestUrl,
        txTime,
        now,
        resourceTypes,
        sinceTime,
        exportLevel,
        patientId,
        groupId,
        typeFilters,
        requestedBy,
      ],
    );
  }

  Future<ExportJob?> getExportJob(String jobId) async {
    final rows = await customSelect(
      'SELECT * FROM export_jobs WHERE job_id = ?',
      variables: [Variable.withString(jobId)],
    ).get();
    if (rows.isEmpty) return null;
    return ExportJob.fromRow(rows.first);
  }

  Future<void> updateExportJob(
    String jobId, {
    String? status,
    String? outputJson,
    String? errorJson,
    DateTime? completedAt,
  }) async {
    final sets = <String>[];
    final values = <Object?>[];
    if (status != null) {
      sets.add('status = ?');
      values.add(status);
    }
    if (outputJson != null) {
      sets.add('output_json = ?');
      values.add(outputJson);
    }
    if (errorJson != null) {
      sets.add('error_json = ?');
      values.add(errorJson);
    }
    if (completedAt != null) {
      sets.add('completed_at = ?');
      values.add(completedAt.millisecondsSinceEpoch ~/ 1000);
    }
    if (sets.isEmpty) return;
    values.add(jobId);
    await customStatement(
      'UPDATE export_jobs SET ${sets.join(', ')} WHERE job_id = ?',
      values,
    );
  }

  Future<void> deleteExportJob(String jobId) async {
    await customStatement(
      'DELETE FROM export_jobs WHERE job_id = ?',
      [jobId],
    );
  }

  /// The finished jobs (completed, error, cancelled) whose `completed_at` is
  /// before [cutoff]: what an export sweep deletes, files and row.
  Future<List<ExportJob>> finishedExportJobsBefore(DateTime cutoff) async {
    final rows = await customSelect(
      "SELECT * FROM export_jobs WHERE status IN ('completed', 'error', "
      "'cancelled') AND completed_at IS NOT NULL AND completed_at < ?",
      variables: [Variable.withInt(cutoff.millisecondsSinceEpoch ~/ 1000)],
    ).get();
    return rows.map(ExportJob.fromRow).toList();
  }

  /// Every job id in the table, for reconciling the export directory.
  Future<Set<String>> exportJobIds() async {
    final rows = await customSelect('SELECT job_id FROM export_jobs').get();
    return rows.map((r) => r.read<String>('job_id')).toSet();
  }

  /// Marks every job still `pending` or `in_progress` as failed. A job runs
  /// as a future in the server process; after a restart nothing is running
  /// it, and without this it would answer 202 to every poll for ever.
  /// Returns how many were marked.
  Future<int> failStaleExportJobs(String reason) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final error = jsonEncode([
      {
        'resourceType': 'OperationOutcome',
        'issue': [
          {'severity': 'error', 'code': 'exception', 'diagnostics': reason},
        ],
      },
    ]);
    return customUpdate(
      "UPDATE export_jobs SET status = 'error', error_json = ?, "
      "completed_at = ? WHERE status IN ('pending', 'in_progress')",
      variables: [Variable.withString(error), Variable.withInt(now)],
      updates: {},
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    await customSelect('SELECT 1').get();
  }

  Future<void> clear() async {
    await batch((batch) {
      batch
        ..deleteWhere(resources, (tbl) => const Constant(true))
        ..deleteWhere(resourcesHistory, (tbl) => const Constant(true))
        ..deleteWhere(stringSearchParameters, (tbl) => const Constant(true))
        ..deleteWhere(tokenSearchParameters, (tbl) => const Constant(true))
        ..deleteWhere(referenceSearchParameters, (tbl) => const Constant(true))
        ..deleteWhere(dateSearchParameters, (tbl) => const Constant(true))
        ..deleteWhere(numberSearchParameters, (tbl) => const Constant(true))
        ..deleteWhere(quantitySearchParameters, (tbl) => const Constant(true))
        ..deleteWhere(uriSearchParameters, (tbl) => const Constant(true))
        ..deleteWhere(compositeSearchParameters, (tbl) => const Constant(true))
        ..deleteWhere(specialSearchParameters, (tbl) => const Constant(true));
      // Note: Logs are intentionally NOT cleared to maintain audit trail
    });
  }
}

/// The backup was written by a newer FHIRant than this one.
class BackupSchemaTooNew implements Exception {
  /// Creates the refusal for a backup at [backupVersion].
  const BackupSchemaTooNew(this.backupVersion, this.thisVersion);

  /// The backup's schema version.
  final int backupVersion;

  /// This database's schema version.
  final int thisVersion;

  @override
  String toString() =>
      'This backup was made by a newer FHIRant (schema $backupVersion; this '
      'one is $thisVersion). Update the app, then restore.';
}

/// The passphrase does not open the file, or it is not a FHIRant backup.
class BackupUnreadable implements Exception {
  /// Creates the failure with the cipher's message.
  const BackupUnreadable(this.detail);

  /// What SQLite said.
  final String detail;

  @override
  String toString() =>
      'That passphrase does not open this file, or the file is not a FHIRant '
      'backup.';
}

/// This SQLite build has no cipher, so nothing here can be encrypted.
class NoCipherInThisBuild implements Exception {
  /// Creates the refusal.
  const NoCipherInThisBuild();

  @override
  String toString() =>
      'This build of SQLite has no cipher (PRAGMA cipher answers nothing): a '
      'backup would be written in the clear, so none is written.';
}
