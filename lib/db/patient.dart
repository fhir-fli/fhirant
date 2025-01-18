part of 'db_service.dart';

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
    INSERT INTO patients (
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
