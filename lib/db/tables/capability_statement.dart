// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [CapabilityStatement] canonical resources
void createCapabilityStatementTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS CapabilityStatement (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date DATETIME,
      title TEXT,
      lastUpdated DATETIME NOT NULL
    );
  ''')
    ..execute(
        'CREATE INDEX IF NOT EXISTS idx_capability_statement_url ON CapabilityStatement (url);')
    ..execute(
        'CREATE INDEX IF NOT EXISTS idx_capability_statement_status ON CapabilityStatement (status);')
    ..execute('''
    CREATE TABLE IF NOT EXISTS CapabilityStatementHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [CapabilityStatement] canonical resource to the database
bool saveCapabilityStatement(Database db, CapabilityStatement resource) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as CapabilityStatement;
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
        'SELECT id FROM CapabilityStatement WHERE id = ?', [id]).isNotEmpty) {
      db.execute('''
        INSERT INTO CapabilityStatementHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM CapabilityStatement WHERE id = ?;
      ''', [id]);
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO CapabilityStatement (
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

/// Get a [CapabilityStatement] canonical resource by its ID
CapabilityStatement? getCapabilityStatement(Database db, String id) {
  try {
    final result = db
        .select('SELECT resource FROM CapabilityStatement WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return CapabilityStatement.fromJsonString(
          result.first['resource'] as String);
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
