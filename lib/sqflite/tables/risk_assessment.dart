// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [RiskAssessment] resources
Future<void> createRiskAssessmentTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS RiskAssessment (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS RiskAssessmentHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [RiskAssessment] to the database
Future<bool> saveRiskAssessment(Database db, RiskAssessment resource) async {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as RiskAssessment;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;

  try {
    // Check if a resource with the same ID exists
    final existingResource = await db.rawQuery(
      'SELECT id, resource, lastUpdated FROM RiskAssessment WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      await db.rawInsert('''
        INSERT INTO RiskAssessmentHistory (
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
      INSERT OR REPLACE INTO RiskAssessment (
        id, lastUpdated, resource
      ) VALUES (?, ?, ?);
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

/// Get a [RiskAssessment] by its ID
Future<RiskAssessment?> getRiskAssessment(Database db, String id) async {
  try {
    final result = await db.rawQuery(
      'SELECT resource FROM RiskAssessment WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return RiskAssessment.fromJsonString(
        result.first['resource']! as String,
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
