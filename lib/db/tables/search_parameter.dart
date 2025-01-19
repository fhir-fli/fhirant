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
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date DATETIME,
      lastUpdated DATETIME NOT NULL
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
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [SearchParameter] canonical resource to the database
bool saveSearchParameter(Database db, SearchParameter resource) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as SearchParameter;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
    final lastUpdated = updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final url = updatedResource.url?.value;
  final status = updatedResource.status?.toString();
  final date = updatedResource.date?.valueDateTime;

  try {
    // Archive old version in the history table
    if (db.select(
      'SELECT id FROM SearchParameter WHERE id = ?',
      [id],
    ).isNotEmpty) {
      db.execute(
        '''
        INSERT INTO SearchParameterHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM SearchParameter WHERE id = ?;
      ''',
        [id],
      );
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO SearchParameter (
        id, url, status, date, title, lastUpdated, resource
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        url = excluded.url,
        status = excluded.status,
        date = excluded.date,
        lastUpdated = excluded.lastUpdated,
        resource = excluded.resource;
    ''', [
      id,
      url,
      status,
      date,
      lastUpdated,
      resourceJson,
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
    final result =
        db.select('SELECT resource FROM SearchParameter WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return SearchParameter.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
