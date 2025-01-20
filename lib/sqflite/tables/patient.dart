import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [Patient] resources
Future<void> createPatientTables(Transaction txn) async {
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS Patient (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      active INTEGER,
      identifier TEXT,
      family_names TEXT,
      given_names TEXT,
      gender TEXT,
      birthDate INT,
      deceased INTEGER,
      managingOrganization TEXT
    );
  ''');
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS PatientHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [Patient] to the database
Future<bool> savePatient(Transaction txn, Patient patient) async {
  final updatedPatient =
      updateMeta(patient, versionIdAsTime: true).newIdIfNoId();
  final id = updatedPatient.id?.value;
  final resourceJson = updatedPatient.toJsonString();
  final lastUpdated =
      updatedPatient.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final activeBoolean = patient.active?.value;
  final active = activeBoolean != null ? (activeBoolean ? 1 : 0) : null;
  final identifier =
      patient.identifier?.map((e) => e.value?.value ?? '').join(',');
  final familyNames = patient.name?.map((n) => n.family?.value ?? '').join(',');
  final givenNames = patient.name
      ?.map((n) => n.given?.map((e) => e.value).join(' '))
      .join(',');
  final gender = patient.gender?.toString();
  final birthDate = patient.birthDate?.valueDateTime?.millisecondsSinceEpoch;
  final deceasedBoolean = patient.deceasedX is FhirBoolean &&
      ((patient.deceasedX! as FhirBoolean).value ?? false);
  final deceased = deceasedBoolean ? 1 : 0;
  final managingOrganization = patient.managingOrganization?.reference?.value;

  try {
    final existingResource = await txn.rawQuery(
      'SELECT id, resource, lastUpdated FROM Patient WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      final oldResource = existingResource.first;
      await txn.rawInsert('''
        INSERT INTO PatientHistory (
          id, lastUpdated, resource
        ) VALUES (?, ?, ?);
      ''', [
        oldResource['id'],
        oldResource['lastUpdated'],
        oldResource['resource'],
      ]);
    }

    await txn.rawInsert('''
    INSERT OR REPLACE INTO Patient (
      id, lastUpdated, resource, active, identifier, family_names, given_names, gender, birthDate, deceased, managingOrganization
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
  ''', [
      id,
      lastUpdated,
      resourceJson,
      active,
      identifier,
      familyNames,
      givenNames,
      gender,
      birthDate,
      deceased,
      managingOrganization,
    ]);
    return true;
  } catch (e) {
    print('Error saving Patient: $e');
    return false;
  }
}

/// Get a [Patient] by its ID
Future<Patient?> getPatient(Transaction txn, String id) async {
  try {
    final result = await txn.rawQuery(
      'SELECT resource FROM Patient WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return Patient.fromJsonString(result.first['resource']! as String);
    }
  } catch (e) {
    print('Error retrieving Patient: $e');
  }
  return null;
}
