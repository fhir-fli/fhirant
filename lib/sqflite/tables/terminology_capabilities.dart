// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [TerminologyCapabilities] canonical resources
Future<void> createTerminologyCapabilitiesTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS TerminologyCapabilities (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date INT,
      title TEXT,
      lastUpdated INT NOT NULL
    );
  ''');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_terminology_capabilities_url ON TerminologyCapabilities (url);',);
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_terminology_capabilities_status ON TerminologyCapabilities (status);',);
  await db.execute('''
    CREATE TABLE IF NOT EXISTS TerminologyCapabilitiesHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [TerminologyCapabilities] canonical resource to the database
Future<bool> saveTerminologyCapabilities(
    Database db, TerminologyCapabilities resource,) async {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as TerminologyCapabilities;
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
    final existingResource = await db.rawQuery(
      'SELECT id, resource, lastUpdated FROM TerminologyCapabilities WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      await db.rawInsert('''
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
    await db.rawInsert('''
      INSERT OR REPLACE INTO TerminologyCapabilities (
        id, url, status, date, title, lastUpdated, resource
      ) VALUES (?, ?, ?, ?, ?, ?, ?);
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

/// Get a [TerminologyCapabilities] canonical resource by its ID
Future<TerminologyCapabilities?> getTerminologyCapabilities(
    Database db, String id,) async {
  try {
    final result = await db.rawQuery(
      'SELECT resource FROM TerminologyCapabilities WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return TerminologyCapabilities.fromJsonString(
        result.first['resource']! as String,
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
