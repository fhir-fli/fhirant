// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:fhir_r4/fhir_r4.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// This class is a singleton that manages the local database for FHIR
/// resources.
class FhirDb {
  /// The singleton instance of the FhirDb.
  factory FhirDb() => _fhirDb;

  FhirDb._internal(); // Private constructor

  static final FhirDb _fhirDb = FhirDb._internal();

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
      throw Exception('Failed to initialize FhirDb: $e');
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
      _db.execute('''
        CREATE TABLE IF NOT EXISTS types (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          resourceType TEXT UNIQUE NOT NULL
        );
      ''');
    }

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
  Future<void> getResourceTable(R4ResourceType resourceType) async {
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
    R4ResourceType resourceType,
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
    R4ResourceType resourceType,
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
    R4ResourceType resourceType,
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
    R4ResourceType resourceType,
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
      UPDATE $resourceType
      SET resourceData = ?, lastUpdated = CURRENT_TIMESTAMP
      WHERE id = ?
      ''',
        [resourceData, id],
      );

      // Check the number of rows affected
      if (_db.updatedRows == 0) {
        throw Exception('Resource with ID $id not found in $resourceType');
      }

      print('Updated resource in $resourceType: $id');
    } catch (e) {
      print('Error updating resource: $e');
      throw Exception('Failed to update resource: $e');
    }
  }

  /// Delete a resource by its ID
  Future<void> deleteResource(R4ResourceType resourceType, String id) async {
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

  /// List all resources of a given type
  Future<List<Map<String, dynamic>>> listResources(
    R4ResourceType resourceType,
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
