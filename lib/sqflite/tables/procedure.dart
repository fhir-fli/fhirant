import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [Procedure] resources
Future<void> createProcedureTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS Procedure (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      patientId TEXT NOT NULL,
      code TEXT NOT NULL,
      performedDateTime INT,
      status TEXT
    );
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_procedure_patientId ON Procedure (patientId);',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_procedure_status ON Procedure (status);',
  );
  await db.execute('''
    CREATE TABLE IF NOT EXISTS ProcedureHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [Procedure] to the database
Future<bool> saveProcedure(Database db, Procedure procedure) async {
  final updatedProcedure =
      updateMeta(procedure, versionIdAsTime: true).newIdIfNoId();
  final id = procedure.id?.value;
  final resourceJson = updatedProcedure.toJsonString();
  final lastUpdated =
      updatedProcedure.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final patientId = procedure.subject.reference?.value;
  final code = procedure.code?.coding?.first.code?.value;
  final performedDateTime = procedure.performedX
      ?.isAs<FhirDateTimeBase>()
      ?.valueDateTime
      ?.millisecondsSinceEpoch;
  final status = procedure.status.toString();

  try {
    final existingResource = await db.rawQuery(
      'SELECT id, resource, lastUpdated FROM Procedure WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      final oldResource = existingResource.first;
      await db.rawInsert('''
        INSERT INTO ProcedureHistory (
          id, lastUpdated, resource
        ) VALUES (?, ?, ?);
      ''', [
        oldResource['id'],
        oldResource['lastUpdated'],
        oldResource['resource'],
      ]);
    }

    await db.rawInsert('''
      INSERT OR REPLACE INTO Procedure (
        id, lastUpdated, resource, patientId, code, performedDateTime, status
      ) VALUES (?, ?, ?, ?, ?, ?, ?);
    ''', [
      id,
      lastUpdated,
      resourceJson,
      patientId,
      code,
      performedDateTime,
      status,
    ]);
    return true;
  } catch (e) {
    print('Error saving Procedure: $e');
    return false;
  }
}

/// Get a [Procedure] by its ID
Future<Procedure?> getProcedure(Database db, String id) async {
  try {
    final result = await db.rawQuery(
      'SELECT resource FROM Procedure WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return Procedure.fromJsonString(result.first['resource']! as String);
    }
  } catch (e) {
    print('Error retrieving Procedure: $e');
  }
  return null;
}
