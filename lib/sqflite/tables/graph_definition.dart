// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [GraphDefinition] canonical resources
Future<void> createGraphDefinitionTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS GraphDefinition (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date INT,
      lastUpdated INT NOT NULL
    );
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_graph_definition_url ON GraphDefinition (url);',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_graph_definition_status ON GraphDefinition (status);',
  );
  await db.execute('''
    CREATE TABLE IF NOT EXISTS GraphDefinitionHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [GraphDefinition] canonical resource to the database
Future<bool> saveGraphDefinition(Database db, GraphDefinition resource) async {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as GraphDefinition;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final url = updatedResource.url?.value;
  final status = updatedResource.status?.toString();
  final date = updatedResource.date?.valueDateTime?.millisecondsSinceEpoch;

  try {
    // Check if a resource with the same ID exists
    final existingResource = await db.rawQuery(
      'SELECT id, resource, lastUpdated FROM GraphDefinition WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      await db.rawInsert('''
        INSERT INTO GraphDefinitionHistory (
          id, lastUpdated, resource
        ) VALUES (?, ?, ?);
      ''', [
        oldResource['id'],
        oldResource['lastUpdated'],
        oldResource['resource'],
      ]);
    }

    // Insert new version into the main table
    await db.rawInsert('''
      INSERT OR REPLACE INTO GraphDefinition (
        id, url, status, date, lastUpdated, resource
      ) VALUES (?, ?, ?, ?, ?, ?);
    ''', [
      id,
      url,
      status,
      date,
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

/// Get a [GraphDefinition] canonical resource by its ID
Future<GraphDefinition?> getGraphDefinition(Database db, String id) async {
  try {
    final result = await db.rawQuery(
      'SELECT resource FROM GraphDefinition WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return GraphDefinition.fromJsonString(
        result.first['resource']! as String,
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
