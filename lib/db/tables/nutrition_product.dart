// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [NutritionProduct] resources
void createNutritionProductTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS NutritionProduct (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS NutritionProductHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [NutritionProduct] to the database
bool saveNutritionProduct(Database db, NutritionProduct resource) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as NutritionProduct;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
    final lastUpdated = updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;

  try {
    // Archive old version in the history table
    if (db.select(
      'SELECT id FROM NutritionProduct WHERE id = ?',
      [id],
    ).isNotEmpty) {
      db.execute(
        '''
        INSERT INTO NutritionProductHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM NutritionProduct WHERE id = ?;
      ''',
        [id],
      );
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO NutritionProduct (
        id, lastUpdated, resource
      ) VALUES (?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        lastUpdated = excluded.lastUpdated,
        resource = excluded.resource;
    ''', [
      id,
      lastUpdated,
      resourceJson,
    ]);

    return true;
  } catch (e) {
    // ignore: avoid_print
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [NutritionProduct] by its ID
NutritionProduct? getNutritionProduct(Database db, String id) {
  try {
    final result =
        db.select('SELECT resource FROM NutritionProduct WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return NutritionProduct.fromJsonString(
        result.first['resource'] as String,
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
