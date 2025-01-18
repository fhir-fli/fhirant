// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [Library] canonical resources
void createLibraryTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Library (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date DATETIME,
      title TEXT,
      lastUpdated DATETIME NOT NULL
    );
  ''')
    ..execute('CREATE INDEX IF NOT EXISTS idx_library_url ON Library (url);')
    ..execute('CREATE INDEX IF NOT EXISTS idx_library_status ON Library (status);')
    ..execute('''
    CREATE TABLE IF NOT EXISTS LibraryHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [Library] canonical resource to the database
bool saveLibrary(Database db, Library resource) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true).newIdIfNoId() as Library;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated = updatedResource.meta?.lastUpdated?.valueDateTime;
  final url = updatedResource.url?.value;
  final status = updatedResource.status?.toString();
  final date = updatedResource.date?.valueDateTime;
  final title = updatedResource.title?.value;

  try {
    // Archive old version in the history table
    if (db.select('SELECT id FROM Library WHERE id = ?', [id]).isNotEmpty) {
      db.execute('''
        INSERT INTO LibraryHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM Library WHERE id = ?;
      ''', [id]);
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO Library (
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
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [Library] canonical resource by its ID
Library? getLibrary(Database db, String id) {
  try {
    final result = db.select('SELECT resource FROM Library WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return Library.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
