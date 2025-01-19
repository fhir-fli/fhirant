// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [ConceptMap] canonical resources
void createConceptMapTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ConceptMap (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date INT,
      title TEXT,
      lastUpdated INT NOT NULL
    );
  ''')
    ..execute(
        'CREATE INDEX IF NOT EXISTS idx_concept_map_url ON ConceptMap (url);')
    ..execute(
        'CREATE INDEX IF NOT EXISTS idx_concept_map_status ON ConceptMap (status);')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ConceptMapHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [ConceptMap] canonical resource to the database
bool saveConceptMap(
  Database db,
  ConceptMap resource,
) {
  final updatedResource =
      updateMeta(resource, versionIdAsTime: true).newIdIfNoId() as ConceptMap;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final url = updatedResource.url?.value;
  final status = updatedResource.status?.toString();
  final date = updatedResource.date?.valueDateTime?.millisecondsSinceEpoch;
  final title = updatedResource.title?.value;

  try {
    // Check if a resource with the same ID exists
    final existingResource = db.select(
      'SELECT id, resource, lastUpdated FROM ConceptMap WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      db.execute('''
        INSERT INTO ConceptMapHistory (
          id, lastUpdated, resource
        ) VALUES (?, ?, ?);
      ''', [
        oldResource['id'],
        oldResource['lastUpdated'],
        oldResource['resource'],
      ]);
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO ConceptMap (
        id, url, status, date, title, lastUpdated, resource
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        url = excluded.url,
        status = excluded.status,
        date = excluded.date,
        title = excluded.title,
        lastUpdated = excluded.lastUpdated,
        resource = excluded.resource;
    ''', [
      id,
      url,
      status,
      date,
      title,
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

/// Get a [ConceptMap] canonical resource by its ID
ConceptMap? getConceptMap(Database db, String id) {
  try {
    final result = db.select(
      'SELECT resource FROM ConceptMap WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return ConceptMap.fromJsonString(
        result.first['resource'] as String,
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
