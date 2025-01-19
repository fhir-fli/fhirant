// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [ActivityDefinition] canonical resources
void createActivityDefinitionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ActivityDefinition (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date INT,
      title TEXT,
      lastUpdated INT NOT NULL
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_activity_definition_url ON ActivityDefinition (url);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_activity_definition_status ON ActivityDefinition (status);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS ActivityDefinitionHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [ActivityDefinition] canonical resource to the database
bool saveActivityDefinition(
  Database db,
  ActivityDefinition resource,
) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as ActivityDefinition;
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
      'SELECT id, resource, lastUpdated FROM ActivityDefinition WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      db.execute('''
        INSERT INTO ActivityDefinitionHistory (
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
      INSERT INTO ActivityDefinition (
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

/// Get a [ActivityDefinition] canonical resource by its ID
ActivityDefinition? getActivityDefinition(Database db, String id) {
  try {
    final result = db.select(
      'SELECT resource FROM ActivityDefinition WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return ActivityDefinition.fromJsonString(
        result.first['resource'] as String,
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
