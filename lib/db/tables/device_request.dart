// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [DeviceRequest] resources
void createDeviceRequestTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS DeviceRequest (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS DeviceRequestHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [DeviceRequest] to the database
bool saveDeviceRequest(Database db, DeviceRequest resource) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as DeviceRequest;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated = updatedResource.meta?.lastUpdated?.valueDateTime;

  try {
    // Archive old version in the history table
    if (db
        .select('SELECT id FROM DeviceRequest WHERE id = ?', [id]).isNotEmpty) {
      db.execute('''
        INSERT INTO DeviceRequestHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM DeviceRequest WHERE id = ?;
      ''', [id]);
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO DeviceRequest (
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
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [DeviceRequest] by its ID
DeviceRequest? getDeviceRequest(Database db, String id) {
  try {
    final result =
        db.select('SELECT resource FROM DeviceRequest WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return DeviceRequest.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
