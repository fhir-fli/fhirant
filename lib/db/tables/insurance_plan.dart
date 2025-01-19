// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [InsurancePlan] resources
void createInsurancePlanTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS InsurancePlan (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS InsurancePlanHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [InsurancePlan] to the database
bool saveInsurancePlan(Database db, InsurancePlan resource) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as InsurancePlan;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
    final lastUpdated = updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;

  try {
    // Archive old version in the history table
    if (db
        .select('SELECT id FROM InsurancePlan WHERE id = ?', [id]).isNotEmpty) {
      db.execute(
        '''
        INSERT INTO InsurancePlanHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM InsurancePlan WHERE id = ?;
      ''',
        [id],
      );
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO InsurancePlan (
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

/// Get a [InsurancePlan] by its ID
InsurancePlan? getInsurancePlan(Database db, String id) {
  try {
    final result =
        db.select('SELECT resource FROM InsurancePlan WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return InsurancePlan.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
