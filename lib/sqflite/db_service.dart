// ignore_for_file: avoid_print, lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant/sqflite/db.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

/// Service to interact with the SQLite database using sqflite
class SqfliteDbService {
  static const _databaseName = 'fhir_clinical_sqflite.db';
  static const _databaseVersion = 1;
  static Database? _db;

  /// Initialize the database
  Future<Database> _initializeDatabase() async {
    final dbPath = await getDatabasesPath();
    final filePath = path.join(dbPath, _databaseName);

    return openDatabase(
      filePath,
      version: _databaseVersion,
      onCreate: (db, version) async {
        await createTables(db);
      },
    );
  }

  /// Get the database instance (lazy initialization)
  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initializeDatabase();
    return _db!;
  }

  /// Save a single resource to the database
  Future<bool> saveResource(Resource resource) async {
    final db = await database;
    try {
      final saveFn =
          saveFunction(resource.resourceType); // Fetch correct save function
      return await saveFn(db, resource); // Pass Database instance
    } catch (e) {
      print('Error saving resource of type ${resource.resourceType}: $e');
      return false;
    }
  }

  /// Bulk save resources of the same type
  Future<bool> bulkSaveResourcesOfSameType<T extends Resource>(
    List<T> resources,
  ) async {
    if (resources.isEmpty) return true;

    final db = await database;
    try {
      await db.transaction((_) async {
        final saveFn = saveFunction(resources.first.resourceType);
        for (final resource in resources) {
          await saveFn(db, resource); // Pass Database instance, not Transaction
        }
      });
      return true;
    } catch (e) {
      print('Error bulk saving resources: $e');
      return false;
    }
  }

  /// Bulk save resources of mixed types
  Future<bool> bulkSaveMixedResources(List<Resource> resources) async {
    if (resources.isEmpty) return true;

    final db = await database;
    try {
      await db.transaction((_) async {
        final groupedResources = <R4ResourceType, List<Resource>>{};

        for (final resource in resources) {
          groupedResources
              .putIfAbsent(resource.resourceType, () => [])
              .add(resource);
        }

        for (final entry in groupedResources.entries) {
          final saveFn = saveFunction(entry.key);
          for (final resource in entry.value) {
            await saveFn(
              db,
              resource,
            ); // Pass Database instance, not Transaction
          }
        }
      });
      return true;
    } catch (e) {
      print('Error bulk saving mixed resources: $e');
      return false;
    }
  }

  /// Close the database connection
  Future<void> close() async {
    final db = await database;
    await db.close();
    _db = null;
  }
}
