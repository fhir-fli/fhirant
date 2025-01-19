// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [ImagingStudy] resources
void createImagingStudyTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ImagingStudy (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ImagingStudyHistory (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [ImagingStudy] to the database
bool saveImagingStudy(Database db, ImagingStudy resource) {
  final updatedResource =
      updateMeta(resource, versionIdAsTime: true).newIdIfNoId() as ImagingStudy;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;

  try {
    // Archive old version in the history table
    if (db
        .select('SELECT id FROM ImagingStudy WHERE id = ?', [id]).isNotEmpty) {
      db.execute(
        '''
        INSERT INTO ImagingStudyHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM ImagingStudy WHERE id = ?;
      ''',
        [id],
      );
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO ImagingStudy (
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

/// Get a [ImagingStudy] by its ID
ImagingStudy? getImagingStudy(Database db, String id) {
  try {
    final result =
        db.select('SELECT resource FROM ImagingStudy WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return ImagingStudy.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
