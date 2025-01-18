// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [RelatedPerson] resources
void createRelatedPersonTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS RelatedPerson (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS RelatedPersonHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [RelatedPerson] to the database
bool saveRelatedPerson(Database db, RelatedPerson resource) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as RelatedPerson;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated = updatedResource.meta?.lastUpdated?.valueDateTime;

  try {
    // Archive old version in the history table
    if (db
        .select('SELECT id FROM RelatedPerson WHERE id = ?', [id]).isNotEmpty) {
      db.execute('''
        INSERT INTO RelatedPersonHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM RelatedPerson WHERE id = ?;
      ''', [id]);
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO RelatedPerson (
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

/// Get a [RelatedPerson] by its ID
RelatedPerson? getRelatedPerson(Database db, String id) {
  try {
    final result =
        db.select('SELECT resource FROM RelatedPerson WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return RelatedPerson.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
