// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [DocumentManifest] resources
void createDocumentManifestTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS DocumentManifest (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS DocumentManifestHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [DocumentManifest] to the database
bool saveDocumentManifest(Database db, DocumentManifest resource) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true).newIdIfNoId() as DocumentManifest;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated = updatedResource.meta?.lastUpdated?.valueDateTime;

  try {
    // Archive old version in the history table
    if (db.select('SELECT id FROM DocumentManifest WHERE id = ?', [id]).isNotEmpty) {
      db.execute('''
        INSERT INTO DocumentManifestHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM DocumentManifest WHERE id = ?;
      ''', [id]);
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO DocumentManifest (
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

/// Get a [DocumentManifest] by its ID
DocumentManifest? getDocumentManifest(Database db, String id) {
  try {
    final result = db.select('SELECT resource FROM DocumentManifest WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return DocumentManifest.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
