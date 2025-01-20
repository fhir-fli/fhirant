import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [MedicationAdministration] resources
Future<void> createMedicationAdministrationTables(Database db)  async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS MedicationAdministration (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      patientId TEXT NOT NULL,
      medicationId TEXT NOT NULL,
      effectiveDateTime INT,
      status TEXT
    );
  ''');
    await db.execute(
      // ignore: lines_longer_than_80_chars
      'CREATE INDEX IF NOT EXISTS idx_medication_admin_patientId ON MedicationAdministration (patientId);',
    )
    await db.execute(
      // ignore: lines_longer_than_80_chars
      'CREATE INDEX IF NOT EXISTS idx_medication_admin_status ON MedicationAdministration (status);',
    )
    await db.execute('''
    CREATE TABLE IF NOT EXISTS MedicationAdministrationHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [MedicationAdministration] to the database
Future<bool> saveMedicationAdministration(
  Database db,
  MedicationAdministration medicationAdmin,
) async {
  final updatedAdmin =
      updateMeta(medicationAdmin, versionIdAsTime: true).newIdIfNoId();
  final id = medicationAdmin.id?.value;
  final resourceJson = updatedAdmin.toJsonString();
  final lastUpdated =
      updatedAdmin.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final patientId = medicationAdmin.subject.reference?.value;
  final medicationId = medicationAdmin.medicationX
          .isAs<CodeableConcept>()
          ?.coding
          ?.first
          .code
          ?.value ??
      medicationAdmin.medicationX
          .isAs<Reference>()
          ?.reference
          ?.value
          ?.split('/')
          .last;
  final effectiveDateTime = medicationAdmin.effectiveX
      .isAs<FhirDateTimeBase>()
      ?.valueDateTime
      ?.millisecondsSinceEpoch;
  final status = medicationAdmin.status.toString();

  try {
    // Check if a resource with the same ID exists
    final existingResource = db.select(
      // ignore: lines_longer_than_80_chars
      'SELECT id, resource, lastUpdated FROM MedicationAdministration WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      await db.execute('''
        INSERT INTO MedicationAdministrationHistory (
          id, lastUpdated, resource
        ) VALUES (?, ?, ?);
      ''', [
        oldResource['id'],
        oldResource['lastUpdated'],
        oldResource['resource'],
      ]);
    }

    await db.execute('''
    INSERT INTO MedicationAdministration (
      id, lastUpdated, resource, patientId, medicationId, effectiveDateTime, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      lastUpdated = excluded.lastUpdated,
      resource = excluded.resource,
      patientId = excluded.patientId,
      medicationId = excluded.medicationId,
      effectiveDateTime = excluded.effectiveDateTime,
      status = excluded.status;
  ''', [
      id,
      lastUpdated,
      resourceJson,
      patientId,
      medicationId,
      effectiveDateTime,
      status,
    ]);
    return true;
  } catch (e) {
    // ignore: avoid_print
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [MedicationAdministration] by its ID
MedicationAdministration? getMedicationAdministration(Database db, String id) {
  try {
    final result = db.select(
      'SELECT resource FROM MedicationAdministration WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return MedicationAdministration.fromJsonString(
        result.first['resource'] as String,
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
