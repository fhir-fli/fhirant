// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [CatalogEntry] resources
void createCatalogEntryTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS CatalogEntry (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS CatalogEntryHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [CatalogEntry] to the database
bool saveCatalogEntry(Database db, CatalogEntry resource) {
  final updatedResource =
      updateMeta(resource, versionIdAsTime: true).newIdIfNoId() as CatalogEntry;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated = updatedResource.meta?.lastUpdated?.valueDateTime;

  try {
    // Archive old version in the history table
    if (db
        .select('SELECT id FROM CatalogEntry WHERE id = ?', [id]).isNotEmpty) {
      db.execute(
        '''
        INSERT INTO CatalogEntryHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM CatalogEntry WHERE id = ?;
      ''',
        [id],
      );
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO CatalogEntry (
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

/// Get a [CatalogEntry] by its ID
CatalogEntry? getCatalogEntry(Database db, String id) {
  try {
    final result =
        db.select('SELECT resource FROM CatalogEntry WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return CatalogEntry.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
