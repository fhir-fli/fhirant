import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [Specimen] resources
void createSpecimenTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Specimen (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL,
      patientId TEXT NOT NULL,
      type TEXT NOT NULL,
      collectedDateTime DATETIME,
      status TEXT
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_specimen_patientId ON Specimen (patientId);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_specimen_status ON Specimen (status);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS SpecimenHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [Specimen] to the database
void saveSpecimen(Database db, Specimen specimen) {
  final updatedSpecimen =
      updateMeta(specimen, versionIdAsTime: true).newIdIfNoId();
  final id = specimen.id?.value;
  final resourceJson = updatedSpecimen.toJsonString();
  final lastUpdated = updatedSpecimen.meta?.lastUpdated?.valueDateTime;
  final patientId = specimen.subject?.reference?.value;
  final type = specimen.type?.coding?.first.code?.value;
  final collectedDateTime =
      specimen.collection?.collectedX?.isAs<FhirDateTimeBase>()?.valueDateTime;
  final status = specimen.status?.toString();

  db.execute('''
    INSERT INTO Specimen (
      id, lastUpdated, resource, patientId, type, collectedDateTime, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      lastUpdated = excluded.lastUpdated,
      resource = excluded.resource,
      patientId = excluded.patientId,
      type = excluded.type,
      collectedDateTime = excluded.collectedDateTime,
      status = excluded.status;
  ''', [
    id,
    lastUpdated,
    resourceJson,
    patientId,
    type,
    collectedDateTime,
    status,
  ]);
}

/// Get a [Specimen] by its ID
Specimen? getSpecimen(Database db, String id) {
  try {
    final result =
        db.select('SELECT resource FROM Specimen WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return Specimen.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
