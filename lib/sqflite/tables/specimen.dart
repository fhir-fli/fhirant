import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [Specimen] resources
Future<void> createSpecimenTables(Transaction txn) async {
  await txn.execute('''
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
  await txn.execute(
    'CREATE INDEX IF NOT EXISTS idx_specimen_patientId ON Specimen (patientId);',
  );
  await txn.execute(
    'CREATE INDEX IF NOT EXISTS idx_specimen_status ON Specimen (status);',
  );
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS SpecimenHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [Specimen] to the database
Future<bool> saveSpecimen(Transaction txn, Specimen specimen) async {
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
    final existingResource = await txn.rawQuery(
      'SELECT id, resource, lastUpdated FROM Specimen WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      final oldResource = existingResource.first;
      await txn.rawInsert('''
        INSERT INTO SpecimenHistory (
          id, lastUpdated, resource
        ) VALUES (?, ?, ?);
      ''', [
        oldResource['id'],
        oldResource['lastUpdated'],
        oldResource['resource'],
      ]);
    }

    await txn.rawInsert('''
      INSERT OR REPLACE INTO Specimen (
        id, lastUpdated, resource, patientId, type, collectedDateTime, status
      ) VALUES (?, ?, ?, ?, ?, ?, ?);
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
    print('Error saving Specimen: $e');
    return false;
  }
}

/// Get a [Specimen] by its ID
Future<Specimen?> getSpecimen(Transaction txn, String id) async {
  try {
    final result = await txn.rawQuery(
      'SELECT resource FROM Specimen WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return Specimen.fromJsonString(result.first['resource']! as String);
    }
  } catch (e) {
    print('Error retrieving Specimen: $e');
  }
  return null;
}
