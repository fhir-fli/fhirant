// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [EventDefinition] canonical resources
void createEventDefinitionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS EventDefinition (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date DATETIME,
      title TEXT,
      lastUpdated DATETIME NOT NULL
    );
  ''')
    ..execute(
        'CREATE INDEX IF NOT EXISTS idx_event_definition_url ON EventDefinition (url);')
    ..execute(
        'CREATE INDEX IF NOT EXISTS idx_event_definition_status ON EventDefinition (status);')
    ..execute('''
    CREATE TABLE IF NOT EXISTS EventDefinitionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [EventDefinition] canonical resource to the database
bool saveEventDefinition(Database db, EventDefinition resource) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as EventDefinition;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated = updatedResource.meta?.lastUpdated?.valueDateTime;
  final url = updatedResource.url?.value;
  final status = updatedResource.status?.toString();
  final date = updatedResource.date?.valueDateTime;
  final title = updatedResource.title?.value;

  try {
    // Archive old version in the history table
    if (db.select(
        'SELECT id FROM EventDefinition WHERE id = ?', [id]).isNotEmpty) {
      db.execute('''
        INSERT INTO EventDefinitionHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM EventDefinition WHERE id = ?;
      ''', [id]);
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO EventDefinition (
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
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [EventDefinition] canonical resource by its ID
EventDefinition? getEventDefinition(Database db, String id) {
  try {
    final result =
        db.select('SELECT resource FROM EventDefinition WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return EventDefinition.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
