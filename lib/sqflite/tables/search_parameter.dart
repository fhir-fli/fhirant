// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [SearchParameter] canonical resources
Future<void> createSearchParameterTables(Transaction txn) async {
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS SearchParameter (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date INT,
      lastUpdated INT NOT NULL
    )
    ''');
  await txn.execute('''
    CREATE INDEX IF NOT EXISTS idx_search_parameter_url
    ON SearchParameter (url)
    ''');
  await txn.execute('''
    CREATE INDEX IF NOT EXISTS idx_search_parameter_status
    ON SearchParameter (status)
    ''');
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS SearchParameterHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    )
    ''');
}

/// Save a [SearchParameter] canonical resource to the database
Future<bool> saveSearchParameter(
    Transaction txn, SearchParameter resource,) async {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as SearchParameter;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final url = updatedResource.url?.value;
  final status = updatedResource.status?.toString();
  final date = updatedResource.date?.valueDateTime?.millisecondsSinceEpoch;

  try {
    final existingResource = await txn.rawQuery(
      'SELECT id, resource, lastUpdated FROM SearchParameter WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      final oldResource = existingResource.first;
      await txn.rawInsert(
        '''
        INSERT INTO SearchParameterHistory (
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
      INSERT OR REPLACE INTO SearchParameter (
        id, url, status, date, lastUpdated, resource
      ) VALUES (?, ?, ?, ?, ?, ?)
      ''',
      [
        id,
        url,
        status,
        date,
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

/// Get a [SearchParameter] canonical resource by its ID
Future<SearchParameter?> getSearchParameter(Transaction txn, String id) async {
  try {
    final result = await txn.rawQuery(
      'SELECT resource FROM SearchParameter WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return SearchParameter.fromJsonString(
        result.first['resource']! as String,
      );
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
