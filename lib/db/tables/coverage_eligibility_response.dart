// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [CoverageEligibilityResponse] resources
void createCoverageEligibilityResponseTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS CoverageEligibilityResponse (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS CoverageEligibilityResponseHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [CoverageEligibilityResponse] to the database
bool saveCoverageEligibilityResponse(
  Database db,
  CoverageEligibilityResponse resource,
) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as CoverageEligibilityResponse;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
    final lastUpdated = updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;

  try {
    // Archive old version in the history table
    if (db.select(
      'SELECT id FROM CoverageEligibilityResponse WHERE id = ?',
      [id],
    ).isNotEmpty) {
      db.execute(
        '''
        INSERT INTO CoverageEligibilityResponseHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM CoverageEligibilityResponse WHERE id = ?;
      ''',
        [id],
      );
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO CoverageEligibilityResponse (
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

/// Get a [CoverageEligibilityResponse] by its ID
CoverageEligibilityResponse? getCoverageEligibilityResponse(
  Database db,
  String id,
) {
  try {
    final result = db.select(
      'SELECT resource FROM CoverageEligibilityResponse WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return CoverageEligibilityResponse.fromJsonString(
        result.first['resource'] as String,
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
