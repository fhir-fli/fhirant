// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [OperationDefinition] canonical resources
void createOperationDefinitionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS OperationDefinition (
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
      'CREATE INDEX IF NOT EXISTS idx_operation_definition_url ON OperationDefinition (url);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_operation_definition_status ON OperationDefinition (status);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS OperationDefinitionHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [OperationDefinition] canonical resource to the database
bool saveOperationDefinition(
  Database db,
  OperationDefinition resource,
) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as OperationDefinition;
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
      'SELECT id, resource, lastUpdated FROM OperationDefinition WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      db.execute('''
        INSERT INTO OperationDefinitionHistory (
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
      INSERT INTO OperationDefinition (
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

/// Get a [OperationDefinition] canonical resource by its ID
OperationDefinition? getOperationDefinition(Database db, String id) {
  try {
    final result = db.select(
      'SELECT resource FROM OperationDefinition WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return OperationDefinition.fromJsonString(
        result.first['resource'] as String,
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
