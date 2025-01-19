import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [Location] resources
void createLocationTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Location (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      name TEXT,
      type TEXT,
      address TEXT,
      managingOrganization TEXT
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_location_name ON Location (name);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS LocationHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [Location] to the database
bool saveLocation(Database db, Location location) {
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
    final existingResource = db.select(
      'SELECT id, resource, lastUpdated FROM Location WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      db.execute('''
        INSERT INTO LocationHistory (
          id, lastUpdated, resource
        ) VALUES (?, ?, ?);
      ''', [
        oldResource['id'],
        oldResource['lastUpdated'],
        oldResource['resource'],
      ]);
    }

    db.execute('''
    INSERT INTO Location (
      id, lastUpdated, resource, name, type, address, managingOrganization
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      lastUpdated = excluded.lastUpdated,
      resource = excluded.resource,
      name = excluded.name,
      type = excluded.type,
      address = excluded.address,
      managingOrganization = excluded.managingOrganization;
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
    // ignore: avoid_print
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [Location] by its ID
Location? getLocation(Database db, String id) {
  try {
    final result =
        db.select('SELECT resource FROM Location WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return Location.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
