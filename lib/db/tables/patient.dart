// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [Patient] resources
void createPatientTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Patient (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
      active INTEGER,
      identifier TEXT,
      family_names TEXT,
      given_names TEXT,
      gender TEXT,
      birthDate INT,
      deceased INTEGER,
      managingOrganization TEXT
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS PatientHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [Patient] to the database
bool savePatient(Database db, Patient patient) {
  final updatedPatient =
      updateMeta(patient, versionIdAsTime: true).newIdIfNoId();
  final id = patient.id?.value;
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
    db.execute('''
    INSERT INTO Patient (
      id, lastUpdated, resource, active, identifier, family_names, given_names, gender, birthDate, deceased, managingOrganization
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      lastUpdated = excluded.lastUpdated,
      resource = excluded.resource,
      active = excluded.active,
      identifier = excluded.identifier,
      family_names = excluded.family_names,
      given_names = excluded.given_names,
      gender = excluded.gender,
      birthDate = excluded.birthDate,
      deceased = excluded.deceased,
      managingOrganization = excluded.managingOrganization;
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
    // ignore: avoid_print
    print('Error saving resource to Patient: $e');
    return false;
  }
}

/// Get a [Patient] by its ID
Patient? getPatient(Database db, String id) {
  try {
    final result = db.select('SELECT resource FROM Patient WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return Patient.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
