// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [Organization] resources
Future<void> createOrganizationTables(Transaction txn) async {
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS Organization (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL
    )
    ''');
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS OrganizationHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    )
    ''');
}

/// Save a [Organization] to the database
Future<bool> saveOrganization(Transaction txn, Organization resource) async {
  final updatedResource =
      updateMeta(resource, versionIdAsTime: true).newIdIfNoId() as Organization;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;

  try {
    final existingResource = await txn.rawQuery(
      'SELECT id, resource, lastUpdated FROM Organization WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      final oldResource = existingResource.first;
      await txn.rawInsert(
        '''
        INSERT INTO OrganizationHistory (
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
      INSERT OR REPLACE INTO Organization (
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

/// Get a [Organization] by its ID
Future<Organization?> getOrganization(Transaction txn, String id) async {
  try {
    final result = await txn.rawQuery(
      'SELECT resource FROM Organization WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return Organization.fromJsonString(
        result.first['resource']! as String,
      );
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
