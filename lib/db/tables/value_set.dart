// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [ValueSet] canonical resources
void createValueSetTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ValueSet (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date INT,
      title TEXT,
      lastUpdated INT NOT NULL
    );
  ''')
    ..execute('CREATE INDEX IF NOT EXISTS idx_value_set_url ON ValueSet (url);')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_value_set_status ON ValueSet (status);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS ValueSetHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [ValueSet] canonical resource to the database
bool saveValueSet(Database db, ValueSet resource) {
  final updatedResource =
      updateMeta(resource, versionIdAsTime: true).newIdIfNoId() as ValueSet;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final url = updatedResource.url?.value;
  final status = updatedResource.status?.toString();
  final date = updatedResource.date?.valueDateTime?.millisecondsSinceEpoch;
  final title = updatedResource.title?.value;

  try {
    // Archive old version in the history table
    if (db.select('SELECT id FROM ValueSet WHERE id = ?', [id]).isNotEmpty) {
      db.execute(
        '''
        INSERT INTO ValueSetHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM ValueSet WHERE id = ?;
      ''',
        [id],
      );
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO ValueSet (
        id, url, status, date, title, lastUpdated, resource
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        url = excluded.url,
        status = excluded.status,
        date = excluded.date,
        title = excluded.title,
        lastUpdated = excluded.lastUpdated,
        resource = excluded.resource;
    ''', [
      id,
      url,
      status,
      date,
      title,
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

/// Get a [ValueSet] canonical resource by its ID
ValueSet? getValueSet(Database db, String id) {
  try {
    final result =
        db.select('SELECT resource FROM ValueSet WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return ValueSet.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
