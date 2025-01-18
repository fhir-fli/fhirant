// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [DeviceMetric] resources
void createDeviceMetricTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS DeviceMetric (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS DeviceMetricHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [DeviceMetric] to the database
bool saveDeviceMetric(Database db, DeviceMetric resource) {
  final updatedResource =
      updateMeta(resource, versionIdAsTime: true).newIdIfNoId() as DeviceMetric;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated = updatedResource.meta?.lastUpdated?.valueDateTime;

  try {
    // Archive old version in the history table
    if (db
        .select('SELECT id FROM DeviceMetric WHERE id = ?', [id]).isNotEmpty) {
      db.execute(
        '''
        INSERT INTO DeviceMetricHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM DeviceMetric WHERE id = ?;
      ''',
        [id],
      );
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO DeviceMetric (
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

/// Get a [DeviceMetric] by its ID
DeviceMetric? getDeviceMetric(Database db, String id) {
  try {
    final result =
        db.select('SELECT resource FROM DeviceMetric WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return DeviceMetric.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
