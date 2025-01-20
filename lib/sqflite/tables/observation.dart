import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [Observation] resources
Future<void> createObservationTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS Observation (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      patientId TEXT NOT NULL,
      type TEXT,
      value TEXT,
      unit TEXT,
      effectiveDateTime INT
    );
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS ObservationHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save an [Observation] to the database
Future<bool> saveObservation(Database db, Observation observation) async {
  final updatedObservation =
      updateMeta(observation, versionIdAsTime: true).newIdIfNoId();
  final id = updatedObservation.id?.value;
  final resourceJson = updatedObservation.toJsonString();
  final lastUpdated = updatedObservation
      .meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final patientId = observation.subject?.reference?.value;
  final type = observation.code.coding?.first.code?.value;
  final value = observation.valueX?.isAs<FhirString>()?.value ??
      observation.valueX?.isAs<Quantity>()?.value.toString();
  final unit = observation.valueX?.isAs<Quantity>()?.unit?.value;
  final effectiveDateTime = observation.effectiveX
      ?.isAs<FhirDateTimeBase>()
      ?.valueDateTime
      ?.millisecondsSinceEpoch;

  try {
    final existingResource = await db.rawQuery(
      'SELECT id, resource, lastUpdated FROM Observation WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      final oldResource = existingResource.first;
      await db.rawInsert('''
        INSERT INTO ObservationHistory (
          id, lastUpdated, resource
        ) VALUES (?, ?, ?);
      ''', [
        oldResource['id'],
        oldResource['lastUpdated'],
        oldResource['resource'],
      ]);
    }

    await db.rawInsert('''
    INSERT OR REPLACE INTO Observation (
      id, lastUpdated, resource, patientId, type, value, unit, effectiveDateTime
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
  ''', [
      id,
      lastUpdated,
      resourceJson,
      patientId,
      type,
      value,
      unit,
      effectiveDateTime,
    ]);
    return true;
  } catch (e) {
    print('Error saving Observation: $e');
    return false;
  }
}

/// Get an [Observation] by its ID
Future<Observation?> getObservation(Database db, String id) async {
  try {
    final result = await db.rawQuery(
      'SELECT resource FROM Observation WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return Observation.fromJsonString(result.first['resource']! as String);
    }
  } catch (e) {
    print('Error retrieving Observation: $e');
  }
  return null;
}
