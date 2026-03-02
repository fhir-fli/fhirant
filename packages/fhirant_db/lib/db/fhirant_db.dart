// ignore_for_file: lines_longer_than_80_chars, avoid_print
import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhir_r4_db/fhir_r4_db.dart';
import 'package:fhirant_db/db/server_types.dart';

/// FHIR ANT server database.
///
/// Extends [FhirDb] (from fhir_r4_db) to reuse all FHIR CRUD, search, history,
/// and search parameter indexing logic. Adds server-specific functionality:
/// Users, ExportJobs, and Logs tables (managed via raw SQL).
class FhirAntDb extends FhirDb {
  FhirAntDb(super.executor) {
    // Server uses timestamp-based version IDs.
    fhirDao.versionIdAsTime = true;
  }

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll(); // Creates FhirDb's 14 tables
          await _createUsersTable();
          await _createExportJobsTable();
          await _createLogsTable();
          await _createIndexes();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await _createUsersTable();
          }
          if (from < 3) {
            await _createExportJobsTable();
          }
          if (from < 4) {
            await customStatement(
                'ALTER TABLE export_jobs ADD COLUMN group_id TEXT');
          }
          if (from < 5) {
            await customStatement(
                'ALTER TABLE export_jobs ADD COLUMN type_filters TEXT');
          }
          if (from < 6) {
            await customStatement('ALTER TABLE users ADD COLUMN scopes TEXT');
          }
          if (from < 7) {
            // FhirDb tables that didn't exist in schema version ≤6
            await m.createTable(syncResources);
            await m.createTable(canonicalResources);
            await m.createTable(generalStorage);
            await _createIndexes();
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
        scopes TEXT
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

  Future<void> _createIndexes() async {
    // Search parameter indexes for performance
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_string_value ON string_search_parameters(string_value)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_token_value ON token_search_parameters(token_value)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_token_system ON token_search_parameters(token_system)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_ref_type ON reference_search_parameters(reference_resource_type)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_ref_id ON reference_search_parameters(reference_id_part)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_ref_identifier_sys ON reference_search_parameters(identifier_system)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_ref_identifier_val ON reference_search_parameters(identifier_value)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_uri_value ON uri_search_parameters(uri_value)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_date_value ON date_search_parameters(date_value)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_number_value ON number_search_parameters(number_value)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_special_value ON special_search_parameters(special_value)');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FHIR Delegation — maintain existing API surface
  // ──────────────────────────────────────────────────────────────────────────

  Future<fhir.Resource?> getResource(
    fhir.R4ResourceType resourceType,
    String id,
  ) =>
      fhirDao.getResource(resourceType, id);

  Future<bool> saveResource(fhir.Resource resource) async {
    try {
      await fhirDao.saveResource(resource);
      return true;
    } catch (e) {
      print('Error in saveResource: $e');
      return false;
    }
  }

  Future<bool> saveResources(List<fhir.Resource> resourcesList) =>
      fhirDao.saveResources(resourcesList);

  Future<bool> deleteResource(
    fhir.R4ResourceType resourceType,
    String id,
  ) =>
      fhirDao.deleteResource(resourceType, id);

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

  Future<List<fhir.Resource>> getResourceHistory(
    fhir.R4ResourceType resourceType,
    String id, {
    DateTime? since,
    DateTime? at,
  }) async {
    final resourceTypeString = resourceType.toString();
    final query = select(resourcesHistory)
      ..where((tbl) {
        var cond =
            tbl.resourceType.equals(resourceTypeString) & tbl.id.equals(id);
        if (at != null) {
          // _at: return the single version current at that point in time
          cond = cond & tbl.lastUpdated.isSmallerOrEqualValue(at);
        } else if (since != null) {
          cond = cond & tbl.lastUpdated.isBiggerThanValue(since);
        }
        return cond;
      })
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.lastUpdated)]);
    if (at != null) {
      query.limit(1);
    }
    final rows = await query.get();
    return rows
        .map((row) => fhir.Resource.fromJsonString(row.resource))
        .toList();
  }

  /// Get history for all resources of a given type, queried directly from the
  /// history table (avoids N+1 queries).
  Future<List<fhir.Resource>> getTypeHistory(
    fhir.R4ResourceType resourceType, {
    DateTime? since,
    DateTime? at,
  }) async {
    if (at != null) {
      // _at: return the latest version per (resourceType, id) where
      // lastUpdated <= at.  Requires a grouped MAX subquery.
      final atSeconds = at.millisecondsSinceEpoch ~/ 1000;
      final resourceTypeString = resourceType.toString();
      final rows = await customSelect(
        'SELECT rh.resource FROM resources_history rh '
        'INNER JOIN ('
        '  SELECT resource_type, id, MAX(last_updated) AS max_lu '
        '  FROM resources_history '
        '  WHERE resource_type = ? AND last_updated <= ? '
        '  GROUP BY resource_type, id'
        ') sub ON rh.resource_type = sub.resource_type '
        '  AND rh.id = sub.id AND rh.last_updated = sub.max_lu '
        'ORDER BY rh.last_updated DESC',
        variables: [
          Variable.withString(resourceTypeString),
          Variable.withInt(atSeconds),
        ],
      ).get();
      return rows
          .map((row) => fhir.Resource.fromJsonString(row.read<String>('resource')))
          .toList();
    }

    final resourceTypeString = resourceType.toString();
    final query = select(resourcesHistory)
      ..where((tbl) {
        var cond = tbl.resourceType.equals(resourceTypeString);
        if (since != null) {
          cond = cond & tbl.lastUpdated.isBiggerThanValue(since);
        }
        return cond;
      })
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.lastUpdated)]);
    final rows = await query.get();
    return rows
        .map((row) => fhir.Resource.fromJsonString(row.resource))
        .toList();
  }

  /// Get history for all resources across all types, queried directly from the
  /// history table (avoids N+1+1 queries).
  Future<List<fhir.Resource>> getSystemHistory({
    DateTime? since,
    DateTime? at,
  }) async {
    if (at != null) {
      // _at: return the latest version per (resourceType, id) where
      // lastUpdated <= at.  Requires a grouped MAX subquery.
      final atSeconds = at.millisecondsSinceEpoch ~/ 1000;
      final rows = await customSelect(
        'SELECT rh.resource FROM resources_history rh '
        'INNER JOIN ('
        '  SELECT resource_type, id, MAX(last_updated) AS max_lu '
        '  FROM resources_history '
        '  WHERE last_updated <= ? '
        '  GROUP BY resource_type, id'
        ') sub ON rh.resource_type = sub.resource_type '
        '  AND rh.id = sub.id AND rh.last_updated = sub.max_lu '
        'ORDER BY rh.last_updated DESC',
        variables: [Variable.withInt(atSeconds)],
      ).get();
      return rows
          .map((row) => fhir.Resource.fromJsonString(row.read<String>('resource')))
          .toList();
    }

    final query = select(resourcesHistory)
      ..where((tbl) {
        if (since != null) {
          return tbl.lastUpdated.isBiggerThanValue(since);
        }
        return const Constant(true);
      })
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.lastUpdated)]);
    final rows = await query.get();
    return rows
        .map((row) => fhir.Resource.fromJsonString(row.resource))
        .toList();
  }

  Future<List<fhir.Resource>> search({
    required fhir.R4ResourceType resourceType,
    Map<String, List<String>>? searchParameters,
    List<HasParameter>? hasParameters,
    int? count,
    int? offset,
    List<String>? sort,
  }) =>
      fhirDao.search(
        resourceType: resourceType,
        searchParameters: searchParameters,
        hasParameters: hasParameters,
        count: count,
        offset: offset,
        sort: sort,
      );

  Future<int> searchCount({
    required fhir.R4ResourceType resourceType,
    Map<String, List<String>>? searchParameters,
    List<HasParameter>? hasParameters,
  }) =>
      fhirDao.searchCount(
        resourceType: resourceType,
        searchParameters: searchParameters,
        hasParameters: hasParameters,
      );

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
          return typeCond & tbl.lastUpdated.isBiggerOrEqualValue(since);
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
  // Server-specific: Compartment search
  // ──────────────────────────────────────────────────────────────────────────

  Future<Map<String, Set<String>>> getCompartmentResourceIds({
    required String compartmentType,
    required String compartmentId,
    required Map<String, List<String>> compartmentDefinition,
    List<String>? typeFilter,
    DateTime? since,
  }) async {
    final result = <String, Set<String>>{};

    for (final entry in compartmentDefinition.entries) {
      final resType = entry.key;
      final searchPaths = entry.value;

      // Skip the focal resource — it is handled by the caller.
      if (searchPaths.isEmpty) continue;

      // If typeFilter is provided, skip types not in the filter.
      if (typeFilter != null && !typeFilter.contains(resType)) continue;

      // Build the OR condition across all search paths for this type.
      Expression<bool> condition =
          referenceSearchParameters.resourceType.equals(resType) &
              referenceSearchParameters.referenceResourceType
                  .equals(compartmentType) &
              referenceSearchParameters.referenceIdPart
                  .equals(compartmentId);

      // Add search path matching — use LIKE with % suffix to handle
      // paths like `Observation.subject.where(resolve() is Patient)`.
      Expression<bool>? pathCondition;
      for (final sp in searchPaths) {
        final like = referenceSearchParameters.searchPath.like('$sp%');
        pathCondition = pathCondition == null ? like : (pathCondition | like);
      }
      if (pathCondition != null) {
        condition = condition & pathCondition;
      }

      // Optional _since filter
      if (since != null) {
        condition = condition &
            referenceSearchParameters.lastUpdated
                .isBiggerOrEqualValue(since);
      }

      final query = selectOnly(referenceSearchParameters)
        ..addColumns([referenceSearchParameters.id])
        ..where(condition);

      final rows = await query.get();
      if (rows.isNotEmpty) {
        final ids =
            rows.map((r) => r.read(referenceSearchParameters.id)!).toSet();
        result[resType] = ids;
      }
    }

    return result;
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
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await customStatement(
      'INSERT INTO users (username, password_hash, salt, role, active, created_at, scopes) '
      'VALUES (?, ?, ?, ?, 1, ?, ?)',
      [username, passwordHash, salt, role, now, scopes],
    );
    final rows =
        await customSelect('SELECT last_insert_rowid() AS id').get();
    return rows.first.read<int>('id');
  }

  Future<void> updateLastLogin(int id) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await customStatement(
      'UPDATE users SET last_login = ? WHERE id = ?',
      [now, id],
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

  // ──────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    await customSelect('SELECT 1').get();
  }

  Future<void> clear() async {
    await batch((batch) {
      batch.deleteWhere(resources, (tbl) => const Constant(true));
      batch.deleteWhere(resourcesHistory, (tbl) => const Constant(true));
      batch.deleteWhere(stringSearchParameters, (tbl) => const Constant(true));
      batch.deleteWhere(tokenSearchParameters, (tbl) => const Constant(true));
      batch.deleteWhere(
          referenceSearchParameters, (tbl) => const Constant(true));
      batch.deleteWhere(dateSearchParameters, (tbl) => const Constant(true));
      batch.deleteWhere(numberSearchParameters, (tbl) => const Constant(true));
      batch.deleteWhere(
          quantitySearchParameters, (tbl) => const Constant(true));
      batch.deleteWhere(uriSearchParameters, (tbl) => const Constant(true));
      batch.deleteWhere(
          compositeSearchParameters, (tbl) => const Constant(true));
      batch.deleteWhere(specialSearchParameters, (tbl) => const Constant(true));
      // Note: Logs are intentionally NOT cleared to maintain audit trail
    });
  }
}
