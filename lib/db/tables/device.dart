// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [Device] resources
void createDeviceTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Device (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS DeviceHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [Device] to the database
bool saveDevice(Database db, Device resource) {
  final updatedResource =
      updateMeta(resource, versionIdAsTime: true).newIdIfNoId() as Device;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
    final lastUpdated = updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;

  try {
    // Archive old version in the history table
    if (db.select('SELECT id FROM Device WHERE id = ?', [id]).isNotEmpty) {
      db.execute(
        '''
        INSERT INTO DeviceHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM Device WHERE id = ?;
      ''',
        [id],
      );
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO Device (
        id, lastUpdated, resource
      ) VALUES (?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        lastUpdated = excluded.lastUpdated,
        resource = excluded.resource;
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

/// Get a [Device] by its ID
Device? getDevice(Database db, String id) {
  try {
    final result = db.select('SELECT resource FROM Device WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return Device.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
