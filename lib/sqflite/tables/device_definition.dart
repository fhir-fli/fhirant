// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [DeviceDefinition] resources
Future<void> createDeviceDefinitionTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS DeviceDefinition (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS DeviceDefinitionHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [DeviceDefinition] to the database
Future<bool> saveDeviceDefinition(
    Database db, DeviceDefinition resource,) async {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as DeviceDefinition;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;

  try {
    // Check if a resource with the same ID exists
    final existingResource = await db.rawQuery(
      'SELECT id, resource, lastUpdated FROM DeviceDefinition WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      await db.rawInsert('''
        INSERT INTO DeviceDefinitionHistory (
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
      INSERT OR REPLACE INTO DeviceDefinition (
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

/// Get a [DeviceDefinition] by its ID
Future<DeviceDefinition?> getDeviceDefinition(Database db, String id) async {
  try {
    final result = await db.rawQuery(
      'SELECT resource FROM DeviceDefinition WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return DeviceDefinition.fromJsonString(
        result.first['resource']! as String,
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
