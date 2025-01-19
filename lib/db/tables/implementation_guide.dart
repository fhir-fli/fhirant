// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [ImplementationGuide] canonical resources
void createImplementationGuideTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ImplementationGuide (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date INT,
      title TEXT,
      lastUpdated INT NOT NULL
    );
  ''')
    ..execute(
        'CREATE INDEX IF NOT EXISTS idx_implementation_guide_url ON ImplementationGuide (url);')
    ..execute(
        'CREATE INDEX IF NOT EXISTS idx_implementation_guide_status ON ImplementationGuide (status);')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ImplementationGuideHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [ImplementationGuide] canonical resource to the database
bool saveImplementationGuide(
  Database db,
  ImplementationGuide resource,
) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as ImplementationGuide;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final url = updatedResource.url?.value;
  final status = updatedResource.status?.toString();
  final date = updatedResource.date?.valueDateTime?.millisecondsSinceEpoch;
  final title = updatedResource.title?.value;

  try {
    // Check if a resource with the same ID exists
    final existingResource = db.select(
      'SELECT id, resource, lastUpdated FROM ImplementationGuide WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      db.execute('''
        INSERT INTO ImplementationGuideHistory (
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
      INSERT INTO ImplementationGuide (
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

/// Get a [ImplementationGuide] canonical resource by its ID
ImplementationGuide? getImplementationGuide(Database db, String id) {
  try {
    final result = db.select(
      'SELECT resource FROM ImplementationGuide WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return ImplementationGuide.fromJsonString(
        result.first['resource'] as String,
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
