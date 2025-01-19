// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [Observation] resources
void createObservationTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Observation (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      patientId TEXT NOT NULL,
      type TEXT,
      value TEXT,
      unit TEXT,
      effectiveDateTime INT
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ObservationHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save an [Observation] to the database
bool saveObservation(Database db, Observation observation) {
  final updatedObservation =
      updateMeta(observation, versionIdAsTime: true).newIdIfNoId();
  final id = observation.id?.value;
  final resourceJson = updatedObservation.toJsonString();
  final lastUpdated = updatedObservation
      .meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final patientId = observation.subject?.reference?.value;
  final type = observation.code.coding?.first.code?.value;
  final value = observation.valueX?.isAs<FhirString>()?.value ??
      observation.valueX?.isAs<Quantity>()?.value.toString();
  final unit = observation.valueX?.isAs<Quantity>()?.unit?.value;
  final effectiveDateTime = observation.effectiveX
      ?.isAs<FhirDateTimeBase>()
      ?.valueDateTime
      ?.millisecondsSinceEpoch;

  try {
    // Check if a resource with the same ID exists
    final existingResource = db.select(
      'SELECT id, resource, lastUpdated FROM Observation WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      db.execute('''
        INSERT INTO ObservationHistory (
          id, lastUpdated, resource
        ) VALUES (?, ?, ?);
      ''', [
        oldResource['id'],
        oldResource['lastUpdated'],
        oldResource['resource'],
      ]);
    }

    db.execute('''
    INSERT INTO Observation (
      id, lastUpdated, resource, patientId, type, value, unit, effectiveDateTime
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      lastUpdated = excluded.lastUpdated,
      resource = excluded.resource,
      patientId = excluded.patientId,
      type = excluded.type,
      value = excluded.value,
      unit = excluded.unit,
      effectiveDateTime = excluded.effectiveDateTime;
  ''', [
      id,
      lastUpdated,
      resourceJson,
      patientId,
      type,
      value,
      unit,
      effectiveDateTime,
    ]);
    return true;
  } catch (e) {
    // ignore: avoid_print
    print('Error saving resource to Observation: $e');
    return false;
  }
}

/// Get a [Observation] by its ID
Observation? getObservation(Database db, String id) {
  try {
    final result =
        db.select('SELECT resource FROM Observation WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return Observation.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
