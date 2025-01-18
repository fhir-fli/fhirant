// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [ExplanationOfBenefit] resources
void createExplanationOfBenefitTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS ExplanationOfBenefit (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ExplanationOfBenefitHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [ExplanationOfBenefit] to the database
bool saveExplanationOfBenefit(Database db, ExplanationOfBenefit resource) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as ExplanationOfBenefit;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated = updatedResource.meta?.lastUpdated?.valueDateTime;

  try {
    // Archive old version in the history table
    if (db.select(
      'SELECT id FROM ExplanationOfBenefit WHERE id = ?',
      [id],
    ).isNotEmpty) {
      db.execute(
        '''
        INSERT INTO ExplanationOfBenefitHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM ExplanationOfBenefit WHERE id = ?;
      ''',
        [id],
      );
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO ExplanationOfBenefit (
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

/// Get a [ExplanationOfBenefit] by its ID
ExplanationOfBenefit? getExplanationOfBenefit(Database db, String id) {
  try {
    final result = db
        .select('SELECT resource FROM ExplanationOfBenefit WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return ExplanationOfBenefit.fromJsonString(
        result.first['resource'] as String,
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
