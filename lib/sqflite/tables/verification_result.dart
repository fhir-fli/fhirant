// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [VerificationResult] resources
Future<void> createVerificationResultTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS VerificationResult (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS VerificationResultHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [VerificationResult] to the database
Future<bool> saveVerificationResult(
    Database db, VerificationResult resource,) async {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as VerificationResult;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;

  try {
    // Check if a resource with the same ID exists
    final existingResource = await db.rawQuery(
      'SELECT id, resource, lastUpdated FROM VerificationResult WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      await db.rawInsert('''
        INSERT INTO VerificationResultHistory (
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
      INSERT OR REPLACE INTO VerificationResult (
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

/// Get a [VerificationResult] by its ID
Future<VerificationResult?> getVerificationResult(
    Database db, String id,) async {
  try {
    final result = await db.rawQuery(
      'SELECT resource FROM VerificationResult WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return VerificationResult.fromJsonString(
        result.first['resource']! as String,
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
