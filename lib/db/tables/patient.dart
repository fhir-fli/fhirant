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
void savePatient(Database db, Patient patient) {
  final updatedPatient =
      updateMeta(patient, versionIdAsTime: true).newIdIfNoId();
  final id = patient.id?.value;
  final resourceJson = updatedPatient.toJsonString();
  final lastUpdated = updatedPatient.meta?.lastUpdated?.valueDateTime;
  final active = patient.active?.value;
  final identifier =
      patient.identifier?.map((e) => e.value?.value ?? '').join(',');
  final familyNames = patient.name?.map((n) => n.family?.value ?? '').join(',');
  final givenNames = patient.name
      ?.map((n) => n.given?.map((e) => e.value).join(' '))
      .join(',');
  final gender = patient.gender?.toString();
  final birthDate = patient.birthDate?.valueDateTime;
  final deceased = patient.deceasedX is FhirBoolean &&
      ((patient.deceasedX! as FhirBoolean).value ?? false);
  final managingOrganization = patient.managingOrganization?.reference?.value;

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
}

/// Get a [Patient] by its ID
Patient? getPatient(Database db, String id) {
  try {
    final result = db.select('SELECT resource FROM Patient WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return Patient.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
