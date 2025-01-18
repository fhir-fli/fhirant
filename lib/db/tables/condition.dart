// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [Condition] resources
void createConditionTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Condition (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS ConditionHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [Condition] to the database
bool saveCondition(Database db, Condition condition) {
  final updatedCondition =
      updateMeta(condition, versionIdAsTime: true).newIdIfNoId();
  final id = condition.id?.value;
  final resourceJson = updatedCondition.toJsonString();
  final lastUpdated = updatedCondition.meta?.lastUpdated?.valueDateTime;
  final patientId = condition.subject.reference?.value;
  final clinicalStatus = condition.clinicalStatus?.coding?.first.code?.value;
  final verificationStatus =
      condition.verificationStatus?.coding?.first.code?.value;
  final code = condition.code?.coding?.first.code?.value;
  final onsetDateTime = condition.onsetX is FhirDateTimeBase
      ? (condition.onsetX! as FhirDateTimeBase).valueDateTime
      : null;

  try {
    db.execute('''
    INSERT INTO Condition (
      id, lastUpdated, resource, patientId, clinicalStatus, verificationStatus, code, onsetDateTime
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      lastUpdated = excluded.lastUpdated,
      resource = excluded.resource,
      patientId = excluded.patientId,
      clinicalStatus = excluded.clinicalStatus,
      verificationStatus = excluded.verificationStatus,
      code = excluded.code,
      onsetDateTime = excluded.onsetDateTime;
  ''', [
      id,
      lastUpdated,
      resourceJson,
      patientId,
      clinicalStatus,
      verificationStatus,
      code,
      onsetDateTime,
    ]);
    return true;
  } catch (e) {
    // ignore: avoid_print
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [Condition] by its ID
Condition? getCondition(Database db, String id) {
  try {
    final result =
        db.select('SELECT resource FROM Condition WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return Condition.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
