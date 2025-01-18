import 'dart:io';
import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant/db/db.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';

/// Service to interact with the SQLite database
class DbService {
  /// Constructor to initialize the database
  DbService() {
    _db = _initializeDatabase();
  }

  static const _databaseName = 'fhir_clinical.db';
  late final Database _db;

  Database _initializeDatabase() {
    final dbPath = path.join(Directory.current.path, _databaseName);
    final db = sqlite3.open(dbPath);

    createTables(db);

    return db;
  }

  /// Save a single resource to the database
  bool saveResource(Resource resource) {
    try {
      final saveFn =
          saveFunction(resource.resourceType); // Use existing function
      return saveFn(_db, resource);
    } catch (e) {
      // Log the error
      // ignore: avoid_print
      print('Error saving resource of type ${resource.resourceType}: $e');
      return false;
    }
  }

  /// Save multiple resources of the same type in a transaction
  bool bulkSaveResourcesOfSameType<T extends Resource>(
    List<T> resources,
  ) {
    if (resources.isEmpty) return true;

    try {
      _db.execute('BEGIN TRANSACTION;'); // Start a transaction

      // Use the save function for the specific type
      final saveFn = saveFunction(resources.first.resourceType);

      for (final resource in resources) {
        saveFn(_db, resource);
      }

      _db.execute('COMMIT;'); // Commit the transaction
      return true;
    } catch (e) {
      _db.execute('ROLLBACK;'); // Rollback on error
      // Log the error
      // ignore: avoid_print
      print('Error saving resources in bulk: $e');
      return false;
    }
  }

  /// Save a mixed list of resources of different types
  bool bulkSaveMixedResources(List<Resource> resources) {
    try {
      // Group resources by their type
      final groupedResources = <R4ResourceType, List<Resource>>{};

      for (final resource in resources) {
        groupedResources
            .putIfAbsent(resource.resourceType, () => [])
            .add(resource);
      }

      _db.execute('BEGIN TRANSACTION;'); // Start a transaction

      // Process each group
      for (final entry in groupedResources.entries) {
        final saveFn =
            saveFunction(entry.key); // Lookup save function once per type
        for (final resource in entry.value) {
          saveFn(_db, resource);
        }
      }

      _db.execute('COMMIT;'); // Commit the transaction
      return true;
    } catch (e) {
      _db.execute('ROLLBACK;'); // Rollback the transaction on error
      // Log the error
      // ignore: avoid_print
      print('Error saving mixed resources: $e');
      return false;
    }
  }

  /// Closes the database connection
  void close() {
    _db.dispose();
  }
}
