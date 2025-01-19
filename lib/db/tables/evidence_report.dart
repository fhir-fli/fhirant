// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [EvidenceReport] resources
void createEvidenceReportTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS EvidenceReport (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS EvidenceReportHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [EvidenceReport] to the database
bool saveEvidenceReport(
  Database db,
  EvidenceReport resource,
) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as EvidenceReport;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;

  try {
    // Check if a resource with the same ID exists
    final existingResource = db.select(
      'SELECT id, resource, lastUpdated FROM EvidenceReport WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      db.execute('''
        INSERT INTO EvidenceReportHistory (
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
      INSERT INTO EvidenceReport (
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

/// Get a [EvidenceReport] by its ID
EvidenceReport? getEvidenceReport(Database db, String id) {
  try {
    final result = db.select(
      'SELECT resource FROM EvidenceReport WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return EvidenceReport.fromJsonString(
        result.first['resource'] as String,
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
