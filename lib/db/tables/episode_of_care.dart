// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [EpisodeOfCare] resources
void createEpisodeOfCareTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS EpisodeOfCare (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS EpisodeOfCareHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [EpisodeOfCare] to the database
bool saveEpisodeOfCare(Database db, EpisodeOfCare resource) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as EpisodeOfCare;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
    final lastUpdated = updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;

  try {
    // Archive old version in the history table
    if (db
        .select('SELECT id FROM EpisodeOfCare WHERE id = ?', [id]).isNotEmpty) {
      db.execute(
        '''
        INSERT INTO EpisodeOfCareHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM EpisodeOfCare WHERE id = ?;
      ''',
        [id],
      );
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO EpisodeOfCare (
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

/// Get a [EpisodeOfCare] by its ID
EpisodeOfCare? getEpisodeOfCare(Database db, String id) {
  try {
    final result =
        db.select('SELECT resource FROM EpisodeOfCare WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return EpisodeOfCare.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
