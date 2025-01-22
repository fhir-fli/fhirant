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
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date INT,
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_graph_definition_url ON GraphDefinition (url);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_graph_definition_status ON GraphDefinition (status);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS GraphDefinitionHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [GraphDefinition] canonical resource to the database
bool saveGraphDefinition(
  Database db,
  GraphDefinition resource,
) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as GraphDefinition;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final url = updatedResource.url?.value;
  final status = updatedResource.status?.toString();
  final date = updatedResource.date?.valueDateTime?.millisecondsSinceEpoch;

  try {
    // Check if a resource with the same ID exists
    final existingResource = db.select(
      'SELECT id, resource, lastUpdated FROM GraphDefinition WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      db.execute('''
        INSERT INTO GraphDefinitionHistory (
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
      INSERT INTO GraphDefinition (
        id, lastUpdated, resource, url, status, date
      ) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        lastUpdated = excluded.lastUpdated,
        resource = excluded.resource,
        url = excluded.url,
        status = excluded.status,
        date = excluded.date,
    ''', [
      id,
      lastUpdated,
      resourceJson,
      url,
      status,
      date,
    ]);

    return true;
  } catch (e) {
    // ignore: avoid_print
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [GraphDefinition] canonical resource by its ID
GraphDefinition? getGraphDefinition(Database db, String id) {
  try {
    final result = db.select(
      'SELECT resource FROM GraphDefinition WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return GraphDefinition.fromJsonString(
        result.first['resource'] as String,
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
