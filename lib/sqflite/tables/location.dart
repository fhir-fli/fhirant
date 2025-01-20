import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [Location] resources
Future<void> createLocationTables(Database db) async {
  await db.execute('''
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
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_location_name ON Location (name);',
  );
  await db.execute('''
    CREATE TABLE IF NOT EXISTS LocationHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [Location] to the database
Future<bool> saveLocation(Database db, Location location) async {
  final updatedLocation =
      updateMeta(location, versionIdAsTime: true).newIdIfNoId();
  final id = location.id?.value;
  final resourceJson = updatedLocation.toJsonString();
  final lastUpdated =
      updatedLocation.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final name = location.name?.value;
  final type = location.type?.first.coding?.first.code?.value;
  final address = location.address?.text?.value;
  final managingOrganization = location.managingOrganization?.reference?.value;

  try {
    // Check if a resource with the same ID exists
    final existingResource = await db.rawQuery(
      'SELECT id, resource, lastUpdated FROM Location WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      await db.rawInsert('''
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
    await db.rawInsert('''
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
    // Log the error
    // ignore: avoid_print
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [Location] by its ID
Future<Location?> getLocation(Database db, String id) async {
  try {
    final result = await db.rawQuery(
      'SELECT resource FROM Location WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return Location.fromJsonString(result.first['resource']! as String);
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
