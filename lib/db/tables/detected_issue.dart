// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [DetectedIssue] resources
void createDetectedIssueTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS DetectedIssue (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS DetectedIssueHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [DetectedIssue] to the database
bool saveDetectedIssue(Database db, DetectedIssue resource) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as DetectedIssue;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
    final lastUpdated = updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;

  try {
    // Archive old version in the history table
    if (db
        .select('SELECT id FROM DetectedIssue WHERE id = ?', [id]).isNotEmpty) {
      db.execute(
        '''
        INSERT INTO DetectedIssueHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM DetectedIssue WHERE id = ?;
      ''',
        [id],
      );
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO DetectedIssue (
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

/// Get a [DetectedIssue] by its ID
DetectedIssue? getDetectedIssue(Database db, String id) {
  try {
    final result =
        db.select('SELECT resource FROM DetectedIssue WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return DetectedIssue.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
