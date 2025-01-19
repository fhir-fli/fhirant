// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [MedicationRequest] resources
void createMedicationRequestTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS MedicationRequest (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      patientId TEXT NOT NULL,
      medicationId TEXT NOT NULL,
      intent TEXT,
      priority TEXT,
      status TEXT
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_medication_request_patientId ON MedicationRequest (patientId);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_medication_request_status ON MedicationRequest (status);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS MedicationRequestHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [MedicationRequest] to the database
bool saveMedicationRequest(Database db, MedicationRequest medicationRequest) {
  final updatedRequest =
      updateMeta(medicationRequest, versionIdAsTime: true).newIdIfNoId();
  final id = medicationRequest.id?.value;
  final resourceJson = updatedRequest.toJsonString();
  final lastUpdated =
      updatedRequest.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final patientId = medicationRequest.subject.reference?.value;
  final medicationId = medicationRequest.medicationX
          .isAs<CodeableConcept>()
          ?.coding
          ?.first
          .code
          ?.value ??
      medicationRequest.medicationX
          .isAs<Reference>()
          ?.reference
          ?.value
          ?.split('/')
          .last;
  final intent = medicationRequest.intent.toString();
  final priority = medicationRequest.priority?.toString();
  final status = medicationRequest.status.toString();

  try {
    // Check if a resource with the same ID exists
    final existingResource = db.select(
      'SELECT id, resource, lastUpdated FROM MedicationRequest WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      db.execute('''
        INSERT INTO MedicationRequestHistory (
          id, lastUpdated, resource
        ) VALUES (?, ?, ?);
      ''', [
        oldResource['id'],
        oldResource['lastUpdated'],
        oldResource['resource'],
      ]);
    }

    db.execute('''
    INSERT INTO MedicationRequest (
      id, lastUpdated, resource, patientId, medicationId, intent, priority, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      lastUpdated = excluded.lastUpdated,
      resource = excluded.resource,
      patientId = excluded.patientId,
      medicationId = excluded.medicationId,
      intent = excluded.intent,
      priority = excluded.priority,
      status = excluded.status;
  ''', [
      id,
      lastUpdated,
      resourceJson,
      patientId,
      medicationId,
      intent,
      priority,
      status,
    ]);
    return true;
  } catch (e) {
    // ignore: avoid_print
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [MedicationRequest] by its ID
MedicationRequest? getMedicationRequest(Database db, String id) {
  try {
    final result =
        db.select('SELECT resource FROM MedicationRequest WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return MedicationRequest.fromJsonString(
        result.first['resource'] as String,
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
