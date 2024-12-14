// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// This class is a singleton that manages the local database for FHIR
/// resources.
class FhirDatabase {
  /// The singleton instance of the FhirDatabase.
  factory FhirDatabase() => _fhirDatabase;

  FhirDatabase._internal(); // Private constructor

  static final FhirDatabase _fhirDatabase = FhirDatabase._internal();

  late Database _db;
  bool _initialized = false;
  Completer<void>? _initCompleter;

  /// Initialize the database with an optional path and password
  Future<void> init({String? path, String? pw}) async {
    if (!_initialized) {
      await _initDb(path: path, pw: pw);
    }
  }

  /// Internal initialization logic
  Future<void> _initDb({String? path, String? pw}) async {
    try {
      final dbFolder = path != null
          ? Directory(p.dirname(path))
          : await Directory.systemTemp.createTemp('fhir_sqlite');
      final dbPath = path ?? p.join(dbFolder.path, 'fhir_database.sqlite');

      // Open the database
      _db = sqlite3.open(dbPath);

      // Verify that SQLCipher is being used
      final cipherVersion = _db.select('PRAGMA cipher_version;');
      if (cipherVersion.isEmpty) {
        throw StateError(
          'SQLCipher library is not available. Check your setup!',
        );
      }

      // Set the encryption key
      _db.execute("PRAGMA key = '${pw ?? 'default_password'}';");

      // Initialize the schema (if necessary)
      _initializeSchema();

      _initialized = true;
    } catch (e) {
      print(
        'Error initializing database: $e',
      );
      throw Exception('Failed to initialize FhirDatabase: $e');
    }
  }

  /// Ensure the database is initialized
  Future<void> _ensureInit({String? path, String? pw}) async {
    if (_initialized) return;

    if (_initCompleter == null) {
      _initCompleter = Completer<void>();
      try {
        await _initDb(path: path, pw: pw);
        _initCompleter?.complete();
      } catch (e) {
        _initCompleter?.completeError(e);
        _initCompleter = null; // Allow retrying after a failure.
        rethrow;
      }
    }

    await _initCompleter?.future;
  }

  /// Initialize the database schema (with versioning)
  void _initializeSchema() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS schema_version (
        id INTEGER PRIMARY KEY,
        version INTEGER NOT NULL
      );
    ''');
    final currentVersion = _db
        .select('SELECT MAX(version) AS version FROM schema_version;')
        .first['version'] as int?;
    if (currentVersion == null || currentVersion < 1) {
      _migrateSchema(0, 1); // Perform initial migration to version 1
    }
  }

  /// Perform schema migrations
  void _migrateSchema(int fromVersion, int toVersion) {
    if (fromVersion < 1) {
      // Existing version 1 migrations
      _db.execute('''
      CREATE TABLE IF NOT EXISTS types (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        resourceType TEXT UNIQUE NOT NULL
      );
    ''');
    }

    if (fromVersion < 2) {
      // Add history table in version 2
      _db.execute('''
      CREATE TABLE IF NOT EXISTS history (
        id TEXT NOT NULL,
        resourceType TEXT NOT NULL,
        resourceData TEXT NOT NULL,
        version INTEGER NOT NULL,
        lastUpdated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id, version)
      );
    ''');
    }

    // Update schema version
    _db.execute(
      'INSERT INTO schema_version (version) VALUES (?);',
      [toVersion],
    );
    print('Database schema migrated to version $toVersion');
  }

  /// Update the database encryption key
  Future<void> updateCipher({String? oldPw, String? newPw}) async {
    await _ensureInit(pw: oldPw);
    if (oldPw == newPw) return;

    try {
      _db.execute("PRAGMA rekey = '${newPw ?? 'new_password'}';");
      print('Encryption key updated successfully.');
    } catch (e) {
      print('Failed to update encryption key: $e');
      throw Exception('Failed to update encryption key: $e');
    }
  }

  /// Get or create a dynamic resource table
  Future<void> getResourceTable(String resourceType) async {
    await _ensureInit();
    final createTableQuery = '''
      CREATE TABLE IF NOT EXISTS $resourceType (
        id TEXT PRIMARY KEY,
        resourceData TEXT NOT NULL,
        lastUpdated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    ''';

    try {
      _db.execute(createTableQuery);
      print('Table for resource type "$resourceType" is ready.');
    } catch (e) {
      print('Error creating or accessing table: $e');
      throw Exception('Failed to create or access table for $resourceType: $e');
    }
  }

  /// List all existing resource tables
  Future<List<String>> listResourceTables() async {
    await _ensureInit();
    final tables = _db.select('SELECT name FROM sqlite_master '
        "WHERE type='table' AND name NOT IN ('schema_version', 'types');");
    return tables.map((row) => row['name'] as String).toList();
  }

  /// Batch insert a list of resources into the database
  Future<void> batchInsert(
    String resourceType,
    List<Map<String, dynamic>> resources,
  ) async {
    await getResourceTable(resourceType); // Ensure the table exists

    try {
      _db.execute('BEGIN TRANSACTION;');
      for (final resource in resources) {
        final id = resource['id'];
        if (id == null) {
          throw ArgumentError('Resource must have an "id" field');
        }
        final resourceData = jsonEncode(resource);

        _db.execute(
          '''
        INSERT OR REPLACE INTO $resourceType (id, resourceData, lastUpdated)
        VALUES (?, ?, CURRENT_TIMESTAMP)
        ''',
          [id, resourceData],
        );
      }
      _db.execute('COMMIT;');
      print('Inserted ${resources.length} resources into $resourceType');
    } catch (e) {
      _db.execute('ROLLBACK;');
      print('Error during batch insert for $resourceType: $e');
      throw Exception('Failed to batch insert resources: $e');
    }
  }

  /// Insert a resource into the database
  Future<void> insertResource(
    String resourceType,
    Map<String, dynamic> resource,
  ) async {
    await getResourceTable(resourceType); // Ensure the table exists
    final id = resource['id'];
    if (id == null) {
      throw ArgumentError('Resource must have an "id" field');
    }
    final resourceData = jsonEncode(resource);

    try {
      _db.execute(
        '''
      INSERT INTO $resourceType (id, resourceData, lastUpdated)
      VALUES (?, ?, CURRENT_TIMESTAMP)
      ''',
        [id, resourceData],
      );
      print('Inserted resource into $resourceType: $id');
    } catch (e) {
      print('Error inserting resource: $e');
      throw Exception('Failed to insert resource: $e');
    }
  }

  /// Retrieve a resource by its ID
  Future<Map<String, dynamic>?> getResource(
    String resourceType,
    String id,
  ) async {
    await getResourceTable(resourceType); // Ensure the table exists

    try {
      final result = _db.select(
        '''
      SELECT resourceData FROM $resourceType WHERE id = ?
      ''',
        [id],
      );

      if (result.isEmpty) {
        return null; // Resource not found
      }

      return jsonDecode(result.first['resourceData'] as String)
          as Map<String, dynamic>;
    } catch (e) {
      print('Error retrieving resource: $e');
      throw Exception('Failed to retrieve resource: $e');
    }
  }

  /// Update an existing resource
  Future<void> updateResource(
    String resourceType,
    Map<String, dynamic> resource,
  ) async {
    await getResourceTable(resourceType); // Ensure the table exists
    final id = resource['id'] as String?;
    if (id == null) {
      throw ArgumentError('Resource must have an "id" field');
    }

    // Save the current version to history before updating
    final currentResource = await getResource(resourceType, id);
    if (currentResource != null) {
      await saveHistory(resourceType, currentResource);
    }

    final resourceData = jsonEncode(resource);

    try {
      _db.execute(
        '''
      UPDATE $resourceType
      SET resourceData = ?, lastUpdated = CURRENT_TIMESTAMP
      WHERE id = ?
      ''',
        [resourceData, id],
      );

      if (_db.updatedRows == 0) {
        throw Exception('Resource with ID $id not found in $resourceType');
      }

      print('Updated resource in $resourceType: $id');
    } catch (e) {
      print('Error updating resource: $e');
      throw Exception('Failed to update resource: $e');
    }
  }

  Future<String> createResource(
    String resourceType,
    Map<String, dynamic> resource,
  ) async {
    await getResourceTable(resourceType); // Ensure the table exists

    final id = resource['id'] as String?;
    if (id == null) {
      throw ArgumentError('Resource must have an "id" field.');
    }

    // Ensure the resource does not already exist
    final existingResource = await getResource(resourceType, id);
    if (existingResource != null) {
      throw Exception('Resource with ID $id already exists in $resourceType.');
    }

    final resourceData = jsonEncode(resource);

    try {
      _db.execute(
        '''
      INSERT INTO $resourceType (id, resourceData, lastUpdated)
      VALUES (?, ?, CURRENT_TIMESTAMP)
      ''',
        [id, resourceData],
      );
      print('Created resource in $resourceType: $id');
      return id;
    } catch (e) {
      print('Error creating resource: $e');
      throw Exception('Failed to create resource: $e');
    }
  }

  /// Delete a resource by its ID
  Future<void> deleteResource(String resourceType, String id) async {
    await getResourceTable(resourceType); // Ensure the table exists

    try {
      _db.execute(
        '''
      DELETE FROM $resourceType WHERE id = ?
      ''',
        [id],
      );

      // Check the number of rows affected
      if (_db.updatedRows == 0) {
        throw Exception('Resource with ID $id not found in $resourceType');
      }

      print('Deleted resource from $resourceType: $id');
    } catch (e) {
      print('Error deleting resource: $e');
      throw Exception('Failed to delete resource: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getHistory(
    String resourceType,
    String id,
  ) async {
    try {
      final result = _db.select(
        '''
      SELECT resourceData FROM history
      WHERE resourceType = ? AND id = ?
      ORDER BY version DESC
      ''',
        [resourceType, id],
      );

      return result
          .map((row) => jsonDecode(row['resourceData'] as String))
          .toList() as List<Map<String, dynamic>>;
    } catch (e) {
      print('Error retrieving history: $e');
      throw Exception('Failed to retrieve history: $e');
    }
  }

  Future<void> saveHistory(
    String resourceType,
    Map<String, dynamic> resource,
  ) async {
    await getResourceTable(resourceType); // Ensure the main table exists

    final id = resource['id'];
    final version = (resource['meta'] as Map<String, dynamic>?)?['versionId'];
    if (id == null || version == null) {
      throw ArgumentError(
        'Resource must have "id" and "meta.versionId" fields.',
      );
    }

    final resourceData = jsonEncode(resource);

    try {
      _db.execute(
        '''
      INSERT INTO history (id, resourceType, resourceData, version, lastUpdated)
      VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
      ''',
        [id, resourceType, resourceData, version],
      );
      print('Saved history for resource $id in $resourceType');
    } catch (e) {
      print('Error saving history: $e');
      throw Exception('Failed to save history: $e');
    }
  }

  /// List all resources of a given type
  Future<List<Map<String, dynamic>>> listResources(
    String resourceType,
  ) async {
    await getResourceTable(resourceType); // Ensure the table exists

    try {
      final result = _db.select(
        '''
      SELECT resourceData FROM $resourceType
      ''',
      );

      return result
          .map((row) => jsonDecode(row['resourceData'] as String))
          .toList() as List<Map<String, dynamic>>;
    } catch (e) {
      print('Error listing resources: $e');
      throw Exception('Failed to list resources: $e');
    }
  }

  /// Close the database connection
  void closeConnection() {
    try {
      _db.dispose();
      print('Database connection closed.');
    } catch (e) {
      print('Error closing the database: $e');
    }
  }
}
