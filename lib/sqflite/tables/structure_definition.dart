// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [StructureDefinition] canonical resources
Future<void> createStructureDefinitionTables(Transaction txn) async {
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS StructureDefinition (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date INT,
      title TEXT,
      lastUpdated INT NOT NULL
    )
    ''');
  await txn.execute('''
    CREATE INDEX IF NOT EXISTS idx_structure_definition_url
    ON StructureDefinition (url)
    ''');
  await txn.execute('''
    CREATE INDEX IF NOT EXISTS idx_structure_definition_status
    ON StructureDefinition (status)
    ''');
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS StructureDefinitionHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    )
    ''');
}

/// Save a [StructureDefinition] canonical resource to the database
Future<bool> saveStructureDefinition(
    Transaction txn, StructureDefinition resource,) async {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as StructureDefinition;
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
      'SELECT id, resource, lastUpdated FROM StructureDefinition WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      final oldResource = existingResource.first;
      await txn.rawInsert(
        '''
        INSERT INTO StructureDefinitionHistory (
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
      INSERT OR REPLACE INTO StructureDefinition (
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

/// Get a [StructureDefinition] canonical resource by its ID
Future<StructureDefinition?> getStructureDefinition(
    Transaction txn, String id,) async {
  try {
    final result = await txn.rawQuery(
      'SELECT resource FROM StructureDefinition WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return StructureDefinition.fromJsonString(
        result.first['resource']! as String,
      );
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
