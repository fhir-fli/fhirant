// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [Location] resources
Future<void> createLocationTables(Transaction txn) async {
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS Location (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      name TEXT,
      type TEXT,
      address TEXT,
      managingOrganization TEXT
    );
  ''');
  await txn.execute(
    'CREATE INDEX IF NOT EXISTS idx_location_name ON Location (name);',
  );
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS LocationHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [Location] to the database
Future<bool> saveLocation(Transaction txn, Location location) async {
  final updatedLocation =
      updateMeta(location, versionIdAsTime: true).newIdIfNoId();
  final id = updatedLocation.id?.value;
  final resourceJson = updatedLocation.toJsonString();
  final lastUpdated =
      updatedLocation.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final name = location.name?.value;
  final type = location.type?.first.coding?.first.code?.value;
  final address = location.address?.text?.value;
  final managingOrganization = location.managingOrganization?.reference?.value;

  try {
    // Check if a resource with the same ID exists
    final existingResource = await txn.rawQuery(
      'SELECT id, resource, lastUpdated FROM Location WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      await txn.rawInsert('''
        INSERT INTO LocationHistory (
          id, lastUpdated, resource
        ) VALUES (?, ?, ?);
      ''', [
        oldResource['id'],
        oldResource['lastUpdated'],
        oldResource['resource'],
      ]);
    }

    // Insert or update the new version in the main table
    await txn.rawInsert('''
      INSERT OR REPLACE INTO Location (
        id, lastUpdated, resource, name, type, address, managingOrganization
      ) VALUES (?, ?, ?, ?, ?, ?, ?);
    ''', [
      id,
      lastUpdated,
      resourceJson,
      name,
      type,
      address,
      managingOrganization,
    ]);
    return true;
  } catch (e) {
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [Location] by its ID
Future<Location?> getLocation(Transaction txn, String id) async {
  try {
    final result = await txn.rawQuery(
      'SELECT resource FROM Location WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return Location.fromJsonString(result.first['resource']! as String);
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
