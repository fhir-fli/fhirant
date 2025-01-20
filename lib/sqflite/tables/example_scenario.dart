// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [ExampleScenario] resources
Future<void> createExampleScenarioTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS ExampleScenario (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS ExampleScenarioHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [ExampleScenario] to the database
Future<bool> saveExampleScenario(Database db, ExampleScenario resource) async {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as ExampleScenario;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;

  try {
    // Check if a resource with the same ID exists
    final existingResource = await db.rawQuery(
      'SELECT id, resource, lastUpdated FROM ExampleScenario WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      await db.rawInsert('''
        INSERT INTO ExampleScenarioHistory (
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
      INSERT OR REPLACE INTO ExampleScenario (
        id, lastUpdated, resource
      ) VALUES (?, ?, ?);
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

/// Get a [ExampleScenario] by its ID
Future<ExampleScenario?> getExampleScenario(Database db, String id) async {
  try {
    final result = await db.rawQuery(
      'SELECT resource FROM ExampleScenario WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return ExampleScenario.fromJsonString(
        result.first['resource']! as String,
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
