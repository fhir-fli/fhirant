import 'dart:io';
import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant/db/db.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';

/// Service to interact with the SQLite database
class DbService {
  DbService() {
    _db = _initializeDatabase();
  }

  static const _databaseName = 'fhir_clinical.db';
  late final Database _db;

  /// Initialize and return the database connection
  Database _initializeDatabase() {
    try {
      final dbPath = path.join(Directory.current.path, _databaseName);
      final db = sqlite3.open(dbPath);

      // Ensure tables are created
      createTables(db);

      return db;
    } catch (e) {
      print('Error initializing database: $e');
      throw Exception('Failed to initialize the database');
    }
  }

  /// Save a single resource to the database
  bool saveResource(Resource resource) {
    try {
      final saveFn =
          saveFunction(resource.resourceType); // Lookup save function
      return saveFn(_db, resource);
    } catch (e) {
      print('Error saving resource of type ${resource.resourceType}: $e');
      return false;
    }
  }

  /// Save multiple resources of the same type in a transaction
  bool bulkSaveResourcesOfSameType<T extends Resource>(List<T> resources) {
    if (resources.isEmpty) return true;

    try {
      _db.execute('BEGIN TRANSACTION;');
      final saveFn = saveFunction(resources.first.resourceType);

      for (final resource in resources) {
        saveFn(_db, resource);
      }

      _db.execute('COMMIT;');
      return true;
    } catch (e) {
      _db.execute('ROLLBACK;');
      print('Error saving resources in bulk: $e');
      return false;
    }
  }

  /// Save a mixed list of resources of different types
  bool bulkSaveMixedResources(List<Resource> resources) {
    try {
      final groupedResources = <R4ResourceType, List<Resource>>{};

      // Group resources by type
      for (final resource in resources) {
        groupedResources
            .putIfAbsent(resource.resourceType, () => [])
            .add(resource);
      }

      _db.execute('BEGIN TRANSACTION;');
      for (final entry in groupedResources.entries) {
        final saveFn = saveFunction(entry.key);
        for (final resource in entry.value) {
          saveFn(_db, resource);
        }
      }

      _db.execute('COMMIT;');
      return true;
    } catch (e) {
      _db.execute('ROLLBACK;');
      print('Error saving mixed resources: $e');
      return false;
    }
  }

  /// Fetch all resources of a specific type
  List<Resource> getAllResources(String resourceType) {
    try {
      final query = 'SELECT resource FROM $resourceType';
      final results = _db.select(query);

      return results.map((row) {
        final resourceJson = row['resource'] as String;
        return Resource.fromJsonString(resourceJson);
      }).toList();
    } catch (e) {
      print('Error retrieving all resources of type $resourceType: $e');
      return [];
    }
  }

  /// Fetch resources with pagination
  List<Resource> getResourcesWithPagination({
    required String resourceType,
    required int count,
    required int offset,
  }) {
    try {
      final query = '''
        SELECT resource 
        FROM $resourceType 
        LIMIT ? OFFSET ?
      ''';

      final results = _db.select(query, [count, offset]);

      return results.map((row) {
        final resourceJson = row['resource'] as String;
        return Resource.fromJsonString(resourceJson);
      }).toList();
    } catch (e) {
      print('Error retrieving paginated resources of type $resourceType: $e');
      return [];
    }
  }

  /// Fetch a specific resource by its ID
  Resource? getResource(String resourceType, String id) {
    try {
      final query = 'SELECT resource FROM $resourceType WHERE id = ?';
      final results = _db.select(query, [id]);

      if (results.isNotEmpty) {
        final resourceJson = results.first['resource'] as String;
        return Resource.fromJsonString(resourceJson);
      }
    } catch (e) {
      print('Error retrieving resource of type $resourceType with ID $id: $e');
    }
    return null;
  }

  /// Update a resource in the database
  bool updateResource(Resource resource) {
    try {
      final updateFn = saveFunction(resource.resourceType);
      return updateFn(_db, resource);
    } catch (e) {
      print('Error updating resource of type ${resource.resourceType}: $e');
      return false;
    }
  }

  /// Delete a resource by its ID
  bool deleteResource(String resourceType, String id) {
    try {
      final deleteQuery = 'DELETE FROM $resourceType WHERE id = ?';
      _db.execute(deleteQuery, [id]);
      return true;
    } catch (e) {
      print('Error deleting resource of type $resourceType with ID $id: $e');
      return false;
    }
  }

  /// Close the database connection
  void close() {
    try {
      _db.dispose();
    } catch (e) {
      print('Error closing database connection: $e');
    }
  }
}
