// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [Person] resources
Future<void> createPersonTables(Transaction txn) async {
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS Person (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL
    )
    ''');
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS PersonHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    )
    ''');
}

/// Save a [Person] to the database
Future<bool> savePerson(Transaction txn, Person resource) async {
  final updatedResource =
      updateMeta(resource, versionIdAsTime: true).newIdIfNoId() as Person;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;

  try {
    final existingResource = await txn.rawQuery(
      'SELECT id, resource, lastUpdated FROM Person WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      final oldResource = existingResource.first;
      await txn.rawInsert(
        '''
        INSERT INTO PersonHistory (
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
      INSERT OR REPLACE INTO Person (
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

/// Get a [Person] by its ID
Future<Person?> getPerson(Transaction txn, String id) async {
  try {
    final result = await txn.rawQuery(
      'SELECT resource FROM Person WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return Person.fromJsonString(
        result.first['resource']! as String,
      );
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
