// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [NamingSystem] resources
void createNamingSystemTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS NamingSystem (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS NamingSystemHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [NamingSystem] to the database
bool saveNamingSystem(Database db, NamingSystem resource) {
  final updatedResource =
      updateMeta(resource, versionIdAsTime: true).newIdIfNoId() as NamingSystem;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated = updatedResource.meta?.lastUpdated?.valueDateTime;

  try {
    // Archive old version in the history table
    if (db
        .select('SELECT id FROM NamingSystem WHERE id = ?', [id]).isNotEmpty) {
      db.execute(
        '''
        INSERT INTO NamingSystemHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM NamingSystem WHERE id = ?;
      ''',
        [id],
      );
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO NamingSystem (
        id, lastUpdated, resource
      ) VALUES (?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        lastUpdated = excluded.lastUpdated,
        resource = excluded.resource;
    ''', [
      id,
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

/// Get a [NamingSystem] by its ID
NamingSystem? getNamingSystem(Database db, String id) {
  try {
    final result =
        db.select('SELECT resource FROM NamingSystem WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return NamingSystem.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
