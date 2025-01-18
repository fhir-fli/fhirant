// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [GraphDefinition] canonical resources
void createGraphDefinitionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS GraphDefinition (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date DATETIME,
      lastUpdated DATETIME NOT NULL
    );
  ''')
    ..execute(
        'CREATE INDEX IF NOT EXISTS idx_graph_definition_url ON GraphDefinition (url);')
    ..execute(
        'CREATE INDEX IF NOT EXISTS idx_graph_definition_status ON GraphDefinition (status);')
    ..execute('''
    CREATE TABLE IF NOT EXISTS GraphDefinitionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [GraphDefinition] canonical resource to the database
bool saveGraphDefinition(Database db, GraphDefinition resource) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as GraphDefinition;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated = updatedResource.meta?.lastUpdated?.valueDateTime;
  final url = updatedResource.url?.value;
  final status = updatedResource.status?.toString();
  final date = updatedResource.date?.valueDateTime;

  try {
    // Archive old version in the history table
    if (db.select(
        'SELECT id FROM GraphDefinition WHERE id = ?', [id]).isNotEmpty) {
      db.execute(
        '''
        INSERT INTO GraphDefinitionHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM GraphDefinition WHERE id = ?;
      ''',
        [id],
      );
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO GraphDefinition (
        id, url, status, date, title, lastUpdated, resource
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        url = excluded.url,
        status = excluded.status,
        date = excluded.date,
        lastUpdated = excluded.lastUpdated,
        resource = excluded.resource;
    ''', [
      id,
      url,
      status,
      date,
      lastUpdated,
      resourceJson,
    ]);

    return true;
  } catch (e) {
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [GraphDefinition] canonical resource by its ID
GraphDefinition? getGraphDefinition(Database db, String id) {
  try {
    final result =
        db.select('SELECT resource FROM GraphDefinition WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return GraphDefinition.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
