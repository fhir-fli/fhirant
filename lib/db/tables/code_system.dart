// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [CodeSystem] canonical resources
void createCodeSystemTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS CodeSystem (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date INT,
      title TEXT
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_code_system_url ON CodeSystem (url);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_code_system_status ON CodeSystem (status);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS CodeSystemHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [CodeSystem] canonical resource to the database
bool saveCodeSystem(
  Database db,
  CodeSystem resource,
) {
  final updatedResource =
      updateMeta(resource, versionIdAsTime: true).newIdIfNoId() as CodeSystem;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final url = updatedResource.url?.value?.toString();
  final status = updatedResource.status?.toString();
  final date = updatedResource.date?.valueDateTime?.millisecondsSinceEpoch;
  final title = updatedResource.title?.value;

  try {
    // Check if a resource with the same ID exists
    final existingResource = db.select(
      'SELECT id, resource, lastUpdated FROM CodeSystem WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      db.execute('''
        INSERT INTO CodeSystemHistory (
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
      INSERT INTO CodeSystem (
        id, lastUpdated, resource, url, status, date, title
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        lastUpdated = excluded.lastUpdated,
        resource = excluded.resource,
        url = excluded.url,
        status = excluded.status,
        date = excluded.date,
        title = excluded.title;
    ''', [
      id,
      lastUpdated,
      resourceJson,
      url,
      status,
      date,
      title,
    ]);

    return true;
  } catch (e) {
    // ignore: avoid_print
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [CodeSystem] canonical resource by its ID
CodeSystem? getCodeSystem(Database db, String id) {
  try {
    final result = db.select(
      'SELECT resource FROM CodeSystem WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return CodeSystem.fromJsonString(
        result.first['resource'] as String,
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
