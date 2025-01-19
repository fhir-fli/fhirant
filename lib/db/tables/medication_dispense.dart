// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [MedicationDispense] resources
void createMedicationDispenseTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS MedicationDispense (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      patientId TEXT NOT NULL,
      medicationId TEXT NOT NULL,
      quantity TEXT,
      daysSupply INTEGER,
      status TEXT
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_med_dispense_patientId ON MedicationDispense (patientId);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_med_dispense_status ON MedicationDispense (status);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS MedicationDispenseHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [MedicationDispense] to the database
bool saveMedicationDispense(
  Database db,
  MedicationDispense medicationDispense,
) {
  final updatedDispense =
      updateMeta(medicationDispense, versionIdAsTime: true).newIdIfNoId();
  final id = medicationDispense.id?.value;
  final resourceJson = updatedDispense.toJsonString();
  final lastUpdated =
      updatedDispense.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final patientId = medicationDispense.subject?.reference?.value;
  final medicationId = medicationDispense.medicationX
          .isAs<CodeableConcept>()
          ?.coding
          ?.first
          .code
          ?.value ??
      medicationDispense.medicationX
          .isAs<Reference>()
          ?.reference
          ?.value
          ?.split('/')
          .last;
  final quantity = medicationDispense.quantity?.value?.toString();
  final daysSupply = medicationDispense.daysSupply?.value;
  final status = medicationDispense.status.toString();

  try {
    // Check if a resource with the same ID exists
    final existingResource = db.select(
      'SELECT id, resource, lastUpdated FROM MedicationDispense WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      db.execute('''
        INSERT INTO MedicationDispenseHistory (
          id, lastUpdated, resource
        ) VALUES (?, ?, ?);
      ''', [
        oldResource['id'],
        oldResource['lastUpdated'],
        oldResource['resource'],
      ]);
    }

    db.execute('''
    INSERT INTO MedicationDispense (
      id, lastUpdated, resource, patientId, medicationId, quantity, daysSupply, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      lastUpdated = excluded.lastUpdated,
      resource = excluded.resource,
      patientId = excluded.patientId,
      medicationId = excluded.medicationId,
      quantity = excluded.quantity,
      daysSupply = excluded.daysSupply,
      status = excluded.status;
  ''', [
      id,
      lastUpdated,
      resourceJson,
      patientId,
      medicationId,
      quantity,
      daysSupply,
      status,
    ]);
    return true;
  } catch (e) {
    // ignore: avoid_print
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [MedicationDispense] by its ID
MedicationDispense? getMedicationDispense(Database db, String id) {
  try {
    final result =
        db.select('SELECT resource FROM MedicationDispense WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return MedicationDispense.fromJsonString(
        result.first['resource'] as String,
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
