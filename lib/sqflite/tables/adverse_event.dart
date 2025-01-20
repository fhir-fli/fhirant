// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [AdverseEvent] resources
Future<void> createAdverseEventTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS AdverseEvent (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS AdverseEventHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [AdverseEvent] to the database
Future<bool> saveAdverseEvent(Database db, AdverseEvent resource) async {
  final updatedResource =
      updateMeta(resource, versionIdAsTime: true).newIdIfNoId() as AdverseEvent;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;

  try {
    // Check if a resource with the same ID exists
    final existingResource = await db.rawQuery(
      'SELECT id, resource, lastUpdated FROM AdverseEvent WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      await db.rawInsert('''
        INSERT INTO AdverseEventHistory (
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
      INSERT OR REPLACE INTO AdverseEvent (
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

/// Get a [AdverseEvent] by its ID
Future<AdverseEvent?> getAdverseEvent(Database db, String id) async {
  try {
    final result = await db.rawQuery(
      'SELECT resource FROM AdverseEvent WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return AdverseEvent.fromJsonString(
        result.first['resource']! as String,
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
