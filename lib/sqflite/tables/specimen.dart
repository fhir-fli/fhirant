import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [Specimen] resources
Future<void> createSpecimenTables(Database db)  async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS Specimen (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      patientId TEXT NOT NULL,
      type TEXT NOT NULL,
      collectedDateTime INT,
      status TEXT
    );
  ''');
    await db.execute(
      // ignore: lines_longer_than_80_chars
      'CREATE INDEX IF NOT EXISTS idx_specimen_patientId ON Specimen (patientId);',
    )
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_specimen_status ON Specimen (status);',
    )
    await db.execute('''
    CREATE TABLE IF NOT EXISTS SpecimenHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [Specimen] to the database
Future<bool> saveSpecimen(Database db, Specimen specimen) {
  final updatedSpecimen =
      updateMeta(specimen, versionIdAsTime: true).newIdIfNoId();
  final id = specimen.id?.value;
  final resourceJson = updatedSpecimen.toJsonString();
  final lastUpdated =
      updatedSpecimen.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final patientId = specimen.subject?.reference?.value;
  final type = specimen.type?.coding?.first.code?.value;
  final collectedDateTime = specimen.collection?.collectedX
      ?.isAs<FhirDateTimeBase>()
      ?.valueDateTime
      ?.millisecondsSinceEpoch;
  final status = specimen.status?.toString();

  try {
    // Check if a resource with the same ID exists
    final existingResource = db.select(
      'SELECT id, resource, lastUpdated FROM Specimen WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      await db.execute('''
        INSERT INTO SpecimenHistory (
          id, lastUpdated, resource
        ) VALUES (?, ?, ?);
      ''', [
        oldResource['id'],
        oldResource['lastUpdated'],
        oldResource['resource'],
      ]);
    }

    await db.execute('''
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
    return true;
  } catch (e) {
    // ignore: avoid_print
    print('Error saving resource to Specimen: $e');
    return false;
  }
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
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
