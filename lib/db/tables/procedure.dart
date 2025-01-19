// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [Procedure] resources
void createProcedureTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Procedure (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      patientId TEXT NOT NULL,
      code TEXT NOT NULL,
      performedDateTime INT,
      status TEXT
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_procedure_patientId ON Procedure (patientId);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_procedure_status ON Procedure (status);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS ProcedureHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [Procedure] to the database
bool saveProcedure(Database db, Procedure procedure) {
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
    // Check if a resource with the same ID exists
    final existingResource = db.select(
      'SELECT id, resource, lastUpdated FROM Procedure WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      db.execute('''
        INSERT INTO ProcedureHistory (
          id, lastUpdated, resource
        ) VALUES (?, ?, ?);
      ''', [
        oldResource['id'],
        oldResource['lastUpdated'],
        oldResource['resource'],
      ]);
    }

    db.execute('''
    INSERT INTO Procedure (
      id, lastUpdated, resource, patientId, code, performedDateTime, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      lastUpdated = excluded.lastUpdated,
      resource = excluded.resource,
      patientId = excluded.patientId,
      code = excluded.code,
      performedDateTime = excluded.performedDateTime,
      status = excluded.status;
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
    // Log the error
    // ignore: avoid_print
    print('Error saving resource to Procedure: $e');
    return false;
  }
}

/// Get a [Procedure] by its ID
Procedure? getProcedure(Database db, String id) {
  try {
    final result =
        db.select('SELECT resource FROM Procedure WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return Procedure.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
