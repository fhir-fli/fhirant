// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [Location] resources
void createLocationTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Location (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS LocationHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [Location] to the database
bool saveLocation(Database db, Location resource) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true).newIdIfNoId() as Location;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated = updatedResource.meta?.lastUpdated?.valueDateTime;

  try {
    // Archive old version in the history table
    if (db.select('SELECT id FROM Location WHERE id = ?', [id]).isNotEmpty) {
      db.execute('''
        INSERT INTO LocationHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM Location WHERE id = ?;
      ''', [id]);
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO Location (
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
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [Location] by its ID
Location? getLocation(Database db, String id) {
  try {
    final result = db.select('SELECT resource FROM Location WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return Location.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
