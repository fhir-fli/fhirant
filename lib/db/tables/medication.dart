// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [Medication] resources
void createMedicationTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Medication (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      code TEXT,
      status TEXT,
      manufacturer TEXT,
      form TEXT
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_medication_code ON Medication (code);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_medication_status ON Medication (status);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS MedicationHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [Medication] to the database
bool saveMedication(Database db, Medication medication) {
  final updatedMedication =
      updateMeta(medication, versionIdAsTime: true).newIdIfNoId();
  final id = medication.id?.value;
  final resourceJson = updatedMedication.toJsonString();
  final lastUpdated = updatedMedication
      .meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final code = medication.code?.coding?.first.code?.value;
  final status = medication.status?.toString();
  final manufacturer = medication.manufacturer?.reference?.value;
  final form = medication.form?.coding?.first.code?.value;

  try {
    // Check if a resource with the same ID exists
    final existingResource = db.select(
      'SELECT id, resource, lastUpdated FROM Medication WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      db.execute('''
        INSERT INTO MedicationHistory (
          id, lastUpdated, resource
        ) VALUES (?, ?, ?);
      ''', [
        oldResource['id'],
        oldResource['lastUpdated'],
        oldResource['resource'],
      ]);
    }

    db.execute('''
    INSERT INTO Medication (
      id, lastUpdated, resource, code, status, manufacturer, form
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      lastUpdated = excluded.lastUpdated,
      resource = excluded.resource,
      code = excluded.code,
      status = excluded.status,
      manufacturer = excluded.manufacturer,
      form = excluded.form;
  ''', [
      id,
      lastUpdated,
      resourceJson,
      code,
      status,
      manufacturer,
      form,
    ]);
    return true;
  } catch (e) {
    // ignore: avoid_print
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [Medication] by its ID
Medication? getMedication(Database db, String id) {
  try {
    final result =
        db.select('SELECT resource FROM Medication WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return Medication.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
