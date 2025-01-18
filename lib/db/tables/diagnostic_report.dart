// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [DiagnosticReport] resources
void createDiagnosticReportTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS DiagnosticReport (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS DiagnosticReportHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [DiagnosticReport] to the database
bool saveDiagnosticReport(Database db, DiagnosticReport resource) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as DiagnosticReport;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated = updatedResource.meta?.lastUpdated?.valueDateTime;

  try {
    // Archive old version in the history table
    if (db.select(
      'SELECT id FROM DiagnosticReport WHERE id = ?',
      [id],
    ).isNotEmpty) {
      db.execute(
        '''
        INSERT INTO DiagnosticReportHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM DiagnosticReport WHERE id = ?;
      ''',
        [id],
      );
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO DiagnosticReport (
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

/// Get a [DiagnosticReport] by its ID
DiagnosticReport? getDiagnosticReport(Database db, String id) {
  try {
    final result =
        db.select('SELECT resource FROM DiagnosticReport WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return DiagnosticReport.fromJsonString(
        result.first['resource'] as String,
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
