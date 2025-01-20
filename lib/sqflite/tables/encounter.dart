// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [Encounter] resources
Future<void> createEncounterTables(Transaction txn) async {
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS Encounter (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      patientId TEXT NOT NULL,
      type TEXT,
      startDateTime INT,
      endDateTime INT,
      status TEXT
    );
  ''');
  await txn.execute(
    'CREATE INDEX IF NOT EXISTS idx_encounter_patientId ON Encounter (patientId);',
  );
  await txn.execute(
    'CREATE INDEX IF NOT EXISTS idx_encounter_status ON Encounter (status);',
  );
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS EncounterHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save an [Encounter] to the database
Future<bool> saveEncounter(Transaction txn, Encounter encounter) async {
  final updatedEncounter =
      updateMeta(encounter, versionIdAsTime: true).newIdIfNoId();
  final id = encounter.id?.value;
  final resourceJson = updatedEncounter.toJsonString();
  final lastUpdated =
      updatedEncounter.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final patientId = encounter.subject?.reference?.value;
  final type = encounter.type?.first.coding?.first.code?.value;
  final startDateTime =
      encounter.period?.start?.valueDateTime?.millisecondsSinceEpoch;
  final endDateTime =
      encounter.period?.end?.valueDateTime?.millisecondsSinceEpoch;
  final status = encounter.status.toString();

  try {
    // Check if a resource with the same ID exists
    final existingResource = await txn.rawQuery(
      'SELECT id, resource, lastUpdated FROM Encounter WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      await txn.rawInsert('''
        INSERT INTO EncounterHistory (
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
      INSERT OR REPLACE INTO Encounter (
        id, lastUpdated, resource, patientId, type, startDateTime, endDateTime, status
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
    ''', [
      id,
      lastUpdated,
      resourceJson,
      patientId,
      type,
      startDateTime,
      endDateTime,
      status,
    ]);

    return true;
  } catch (e) {
    print('Error saving resource: $e');
    return false;
  }
}

/// Get an [Encounter] by its ID
Future<Encounter?> getEncounter(Transaction txn, String id) async {
  try {
    final result = await txn.rawQuery(
      'SELECT resource FROM Encounter WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return Encounter.fromJsonString(result.first['resource']! as String);
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
