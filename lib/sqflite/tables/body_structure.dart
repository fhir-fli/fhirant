// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [BodyStructure] resources
Future<void> createBodyStructureTables(Transaction txn) async {
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS BodyStructure (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL
    )
    ''');
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS BodyStructureHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    )
    ''');
}

/// Save a [BodyStructure] to the database
Future<bool> saveBodyStructure(Transaction txn, BodyStructure resource) async {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as BodyStructure;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;

  try {
    final existingResource = await txn.rawQuery(
      'SELECT id, resource, lastUpdated FROM BodyStructure WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      final oldResource = existingResource.first;
      await txn.rawInsert(
        '''
        INSERT INTO BodyStructureHistory (
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
      INSERT OR REPLACE INTO BodyStructure (
        id, lastUpdated, resource
      ) VALUES (?, ?, ?)
      ''',
      [
        id,
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

/// Get a [BodyStructure] by its ID
Future<BodyStructure?> getBodyStructure(Transaction txn, String id) async {
  try {
    final result = await txn.rawQuery(
      'SELECT resource FROM BodyStructure WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return BodyStructure.fromJsonString(
        result.first['resource']! as String,
      );
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
