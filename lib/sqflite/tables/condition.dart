// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [Condition] resources
Future<void> createConditionTables(Transaction txn) async {
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS Condition (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      patientId TEXT NOT NULL,
      clinicalStatus TEXT,
      verificationStatus TEXT,
      code TEXT,
      onsetDateTime INT
    );
  ''');
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS ConditionHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [Condition] to the database
Future<bool> saveCondition(Transaction txn, Condition condition) async {
  final updatedCondition =
      updateMeta(condition, versionIdAsTime: true).newIdIfNoId();
  final id = updatedCondition.id?.value;
  final resourceJson = updatedCondition.toJsonString();
  final lastUpdated =
      updatedCondition.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final patientId = condition.subject.reference?.value;
  final clinicalStatus = condition.clinicalStatus?.coding?.first.code?.value;
  final verificationStatus =
      condition.verificationStatus?.coding?.first.code?.value;
  final code = condition.code?.coding?.first.code?.value;
  final onsetDateTime = condition.onsetX is FhirDateTimeBase
      ? (condition.onsetX! as FhirDateTimeBase)
          .valueDateTime
          ?.millisecondsSinceEpoch
      : null;

  try {
    // Check if a resource with the same ID exists
    final existingResource = await txn.rawQuery(
      'SELECT id, resource, lastUpdated FROM Condition WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      await txn.rawInsert('''
        INSERT INTO ConditionHistory (
          id, lastUpdated, resource
        ) VALUES (?, ?, ?);
      ''', [
        oldResource['id'],
        oldResource['lastUpdated'],
        oldResource['resource'],
      ]);
    }

    // Insert or update the new version in the main table
    await txn.rawInsert('''
      INSERT OR REPLACE INTO Condition (
        id, lastUpdated, resource, patientId, clinicalStatus, verificationStatus, code, onsetDateTime
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
    ''', [
      id,
      lastUpdated,
      resourceJson,
      patientId,
      clinicalStatus,
      verificationStatus,
      code,
      onsetDateTime,
    ]);

    return true;
  } catch (e) {
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [Condition] by its ID
Future<Condition?> getCondition(Transaction txn, String id) async {
  try {
    final result = await txn.rawQuery(
      'SELECT resource FROM Condition WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return Condition.fromJsonString(result.first['resource']! as String);
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
