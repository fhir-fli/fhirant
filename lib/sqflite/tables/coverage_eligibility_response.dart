// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [CoverageEligibilityResponse] resources
Future<void> createCoverageEligibilityResponseTables(Database db)  async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS CoverageEligibilityResponse (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
    await db.execute('''
    CREATE TABLE IF NOT EXISTS CoverageEligibilityResponseHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [CoverageEligibilityResponse] to the database
Future<bool> saveCoverageEligibilityResponse(
  Database db,
  CoverageEligibilityResponse resource,
) async {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as CoverageEligibilityResponse;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;

  try {
    // Check if a resource with the same ID exists
    final existingResource = db.select(
      'SELECT id, resource, lastUpdated FROM CoverageEligibilityResponse WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      await db.execute('''
        INSERT INTO CoverageEligibilityResponseHistory (
          id, lastUpdated, resource
        ) VALUES (?, ?, ?);
      ''', [
        oldResource['id'],
        oldResource['lastUpdated'],
        oldResource['resource'],
      ]);
    }

    // Insert new version into the main table
    await db.execute('''
      INSERT INTO CoverageEligibilityResponse (
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

/// Get a [CoverageEligibilityResponse] by its ID
CoverageEligibilityResponse? getCoverageEligibilityResponse(
  Database db,
  String id,
) {
  try {
    final result = db.select(
      'SELECT resource FROM CoverageEligibilityResponse WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return CoverageEligibilityResponse.fromJsonString(
        result.first['resource'] as String,
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
