// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [OrganizationAffiliation] resources
void createOrganizationAffiliationTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS OrganizationAffiliation (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS OrganizationAffiliationHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [OrganizationAffiliation] to the database
bool saveOrganizationAffiliation(Database db, OrganizationAffiliation resource) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true).newIdIfNoId() as OrganizationAffiliation;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated = updatedResource.meta?.lastUpdated?.valueDateTime;

  try {
    // Archive old version in the history table
    if (db.select('SELECT id FROM OrganizationAffiliation WHERE id = ?', [id]).isNotEmpty) {
      db.execute('''
        INSERT INTO OrganizationAffiliationHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM OrganizationAffiliation WHERE id = ?;
      ''', [id]);
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO OrganizationAffiliation (
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
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [OrganizationAffiliation] by its ID
OrganizationAffiliation? getOrganizationAffiliation(Database db, String id) {
  try {
    final result = db.select('SELECT resource FROM OrganizationAffiliation WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return OrganizationAffiliation.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
