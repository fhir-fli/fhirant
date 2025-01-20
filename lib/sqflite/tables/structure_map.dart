// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [StructureMap] canonical resources
Future<void> createStructureMapTables(Transaction txn) async {
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS StructureMap (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date INT,
      title TEXT,
      lastUpdated INT NOT NULL
    )
    ''');
  await txn.execute('''
    CREATE INDEX IF NOT EXISTS idx_structure_map_url
    ON StructureMap (url)
    ''');
  await txn.execute('''
    CREATE INDEX IF NOT EXISTS idx_structure_map_status
    ON StructureMap (status)
    ''');
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS StructureMapHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    )
    ''');
}

/// Save a [StructureMap] canonical resource to the database
Future<bool> saveStructureMap(Transaction txn, StructureMap resource) async {
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
    final existingResource = await txn.rawQuery(
      'SELECT id, resource, lastUpdated FROM StructureMap WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      final oldResource = existingResource.first;
      await txn.rawInsert(
        '''
        INSERT INTO StructureMapHistory (
          id, lastUpdated, resource
        ) VALUES (?, ?, ?)
        ''',
        [
          oldResource['id'],
          oldResource['lastUpdated'],
          oldResource['resource'],
        ],
      );
    }

    await txn.rawInsert(
      '''
      INSERT OR REPLACE INTO StructureMap (
        id, url, status, date, title, lastUpdated, resource
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        id,
        url,
        status,
        date,
        title,
        lastUpdated,
        resourceJson,
      ],
    );

    return true;
  } catch (e) {
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [StructureMap] canonical resource by its ID
Future<StructureMap?> getStructureMap(Transaction txn, String id) async {
  try {
    final result = await txn.rawQuery(
      'SELECT resource FROM StructureMap WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return StructureMap.fromJsonString(
        result.first['resource']! as String,
      );
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
