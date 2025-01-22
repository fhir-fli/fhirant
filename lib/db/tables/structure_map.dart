// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [StructureMap] canonical resources
void createStructureMapTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS StructureMap (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date INT,
      title TEXT
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_structure_map_url ON StructureMap (url);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_structure_map_status ON StructureMap (status);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS StructureMapHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [StructureMap] canonical resource to the database
bool saveStructureMap(
  Database db,
  StructureMap resource,
) {
  final updatedResource =
      updateMeta(resource, versionIdAsTime: true).newIdIfNoId() as StructureMap;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final url = updatedResource.url?.value;
  final status = updatedResource.status?.toString();
  final date = updatedResource.date?.valueDateTime?.millisecondsSinceEpoch;
  final title = updatedResource.title?.value;

  try {
    // Check if a resource with the same ID exists
    final existingResource = db.select(
      'SELECT id, resource, lastUpdated FROM StructureMap WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      db.execute('''
        INSERT INTO StructureMapHistory (
          id, lastUpdated, resource
        ) VALUES (?, ?, ?);
      ''', [
        oldResource['id'],
        oldResource['lastUpdated'],
        oldResource['resource'],
      ]);
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO StructureMap (
        id, lastUpdated, resource, url, status, date, title
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        lastUpdated = excluded.lastUpdated,
        resource = excluded.resource,
        url = excluded.url,
        status = excluded.status,
        date = excluded.date,
        title = excluded.title;
    ''', [
      id,
      lastUpdated,
      resourceJson,
      url,
      status,
      date,
      title,
    ]);

    return true;
  } catch (e) {
    // ignore: avoid_print
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [StructureMap] canonical resource by its ID
StructureMap? getStructureMap(Database db, String id) {
  try {
    final result = db.select(
      'SELECT resource FROM StructureMap WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return StructureMap.fromJsonString(
        result.first['resource'] as String,
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
