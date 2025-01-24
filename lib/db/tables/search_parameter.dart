// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [SearchParameter] canonical resources
void createSearchParameterTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS SearchParameter (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date INT
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_search_parameter_url ON SearchParameter (url);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_search_parameter_status ON SearchParameter (status);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS SearchParameterHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [SearchParameter] canonical resource to the database
bool saveSearchParameter(
  Database db,
  SearchParameter resource,
) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as SearchParameter;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final url = updatedResource.url?.value?.toString();
  final status = updatedResource.status?.toString();
  final date = updatedResource.date?.valueDateTime?.millisecondsSinceEpoch;

  try {
    // Check if a resource with the same ID exists
    final existingResource = db.select(
      'SELECT id, resource, lastUpdated FROM SearchParameter WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      db.execute('''
        INSERT INTO SearchParameterHistory (
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
      INSERT INTO SearchParameter (
        id, lastUpdated, resource, url, status, date
      ) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        lastUpdated = excluded.lastUpdated,
        resource = excluded.resource,
        url = excluded.url,
        status = excluded.status,
        date = excluded.date;
    ''', [
      id,
      lastUpdated,
      resourceJson,
      url,
      status,
      date,
    ]);

    return true;
  } catch (e) {
    // ignore: avoid_print
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [SearchParameter] canonical resource by its ID
SearchParameter? getSearchParameter(Database db, String id) {
  try {
    final result = db.select(
      'SELECT resource FROM SearchParameter WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return SearchParameter.fromJsonString(
        result.first['resource'] as String,
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
