// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [Encounter] resources
void createEncounterTables(Database db) {
  db
    ..execute('''
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
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_encounter_patientId ON Encounter (patientId);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_encounter_status ON Encounter (status);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS EncounterHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save an [Encounter] to the database
bool saveEncounter(Database db, Encounter encounter) {
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
    db.execute('''
    INSERT INTO Encounter (
      id, lastUpdated, resource, patientId, type, startDateTime, endDateTime, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      lastUpdated = excluded.lastUpdated,
      resource = excluded.resource,
      patientId = excluded.patientId,
      type = excluded.type,
      startDateTime = excluded.startDateTime,
      endDateTime = excluded.endDateTime,
      status = excluded.status;
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
    // ignore: avoid_print
    print('Error saving resource: $e');
    return false;
  }
}

/// Get an [Encounter] by its ID
Encounter? getEncounter(Database db, String id) {
  try {
    final result =
        db.select('SELECT resource FROM Encounter WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return Encounter.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
