// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [TerminologyCapabilities] canonical resources
void createTerminologyCapabilitiesTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS TerminologyCapabilities (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date INT,
      title TEXT
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_terminology_capabilities_url ON TerminologyCapabilities (url);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_terminology_capabilities_status ON TerminologyCapabilities (status);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS TerminologyCapabilitiesHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [TerminologyCapabilities] canonical resource to the database
bool saveTerminologyCapabilities(
  Database db,
  TerminologyCapabilities resource,
) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as TerminologyCapabilities;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final url = updatedResource.url?.value?.toString();
  final status = updatedResource.status?.toString();
  final date = updatedResource.date?.valueDateTime?.millisecondsSinceEpoch;
  final title = updatedResource.title?.value;

  try {
    // Check if a resource with the same ID exists
    final existingResource = db.select(
      'SELECT id, resource, lastUpdated FROM TerminologyCapabilities WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      db.execute('''
        INSERT INTO TerminologyCapabilitiesHistory (
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
      INSERT INTO TerminologyCapabilities (
        id, lastUpdated, resource, url, status, date, title
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        lastUpdated = excluded.lastUpdated,
        resource = excluded.resource,
        url = excluded.url,
        status = excluded.status,
        date = excluded.date,
        title = excluded.title;
    ''', [
      id,
      lastUpdated,
      resourceJson,
      url,
      status,
      date,
      title,
    ]);

    return true;
  } catch (e) {
    // ignore: avoid_print
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [TerminologyCapabilities] canonical resource by its ID
TerminologyCapabilities? getTerminologyCapabilities(Database db, String id) {
  try {
    final result = db.select(
      'SELECT resource FROM TerminologyCapabilities WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return TerminologyCapabilities.fromJsonString(
        result.first['resource'] as String,
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
