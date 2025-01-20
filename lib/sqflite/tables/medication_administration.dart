import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [MedicationAdministration] resources
Future<void> createMedicationAdministrationTables(Database db) async {
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
    'CREATE INDEX IF NOT EXISTS idx_medication_admin_patientId ON MedicationAdministration (patientId);',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_medication_admin_status ON MedicationAdministration (status);',
  );
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
  final id = updatedAdmin.id?.value;
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
    final existingResource = await db.rawQuery(
      'SELECT id, resource, lastUpdated FROM MedicationAdministration WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      final oldResource = existingResource.first;
      await db.rawInsert('''
        INSERT INTO MedicationAdministrationHistory (
          id, lastUpdated, resource
        ) VALUES (?, ?, ?);
      ''', [
        oldResource['id'],
        oldResource['lastUpdated'],
        oldResource['resource'],
      ]);
    }

    await db.rawInsert('''
      INSERT OR REPLACE INTO MedicationAdministration (
        id, lastUpdated, resource, patientId, medicationId, effectiveDateTime, status
      ) VALUES (?, ?, ?, ?, ?, ?, ?);
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
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [MedicationAdministration] by its ID
Future<MedicationAdministration?> getMedicationAdministration(
  Database db,
  String id,
) async {
  try {
    final result = await db.rawQuery(
      'SELECT resource FROM MedicationAdministration WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return MedicationAdministration.fromJsonString(
        result.first['resource']! as String,
      );
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
