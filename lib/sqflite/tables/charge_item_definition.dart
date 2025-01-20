// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [ChargeItemDefinition] resources
Future<void> createChargeItemDefinitionTables(Transaction txn) async {
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS ChargeItemDefinition (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL
    )
    ''');
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS ChargeItemDefinitionHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    )
    ''');
}

/// Save a [ChargeItemDefinition] to the database
Future<bool> saveChargeItemDefinition(
    Transaction txn, ChargeItemDefinition resource,) async {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as ChargeItemDefinition;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;

  try {
    final existingResource = await txn.rawQuery(
      'SELECT id, resource, lastUpdated FROM ChargeItemDefinition WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      final oldResource = existingResource.first;
      await txn.rawInsert(
        '''
        INSERT INTO ChargeItemDefinitionHistory (
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
      INSERT OR REPLACE INTO ChargeItemDefinition (
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

/// Get a [ChargeItemDefinition] by its ID
Future<ChargeItemDefinition?> getChargeItemDefinition(
    Transaction txn, String id,) async {
  try {
    final result = await txn.rawQuery(
      'SELECT resource FROM ChargeItemDefinition WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return ChargeItemDefinition.fromJsonString(
        result.first['resource']! as String,
      );
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
