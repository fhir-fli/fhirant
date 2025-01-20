// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [ResearchStudy] resources
Future<void> createResearchStudyTables(Transaction txn) async {
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS ResearchStudy (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL
    )
    ''');
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS ResearchStudyHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    )
    ''');
}

/// Save a [ResearchStudy] to the database
Future<bool> saveResearchStudy(Transaction txn, ResearchStudy resource) async {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as ResearchStudy;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;

  try {
    final existingResource = await txn.rawQuery(
      'SELECT id, resource, lastUpdated FROM ResearchStudy WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      final oldResource = existingResource.first;
      await txn.rawInsert(
        '''
        INSERT INTO ResearchStudyHistory (
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
      INSERT OR REPLACE INTO ResearchStudy (
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

/// Get a [ResearchStudy] by its ID
Future<ResearchStudy?> getResearchStudy(Transaction txn, String id) async {
  try {
    final result = await txn.rawQuery(
      'SELECT resource FROM ResearchStudy WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return ResearchStudy.fromJsonString(
        result.first['resource']! as String,
      );
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
