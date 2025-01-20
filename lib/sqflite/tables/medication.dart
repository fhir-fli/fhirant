import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [Medication] resources
Future<void> createMedicationTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS Medication (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      code TEXT,
      status TEXT,
      manufacturer TEXT,
      form TEXT
    );
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_medication_code ON Medication (code);',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_medication_status ON Medication (status);',
  );
  await db.execute('''
    CREATE TABLE IF NOT EXISTS MedicationHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [Medication] to the database
Future<bool> saveMedication(Database db, Medication medication) async {
  final updatedMedication =
      updateMeta(medication, versionIdAsTime: true).newIdIfNoId();
  final id = updatedMedication.id?.value;
  final resourceJson = updatedMedication.toJsonString();
  final lastUpdated = updatedMedication
      .meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final code = medication.code?.coding?.first.code?.value;
  final status = medication.status?.toString();
  final manufacturer = medication.manufacturer?.reference?.value;
  final form = medication.form?.coding?.first.code?.value;

  try {
    final existingResource = await db.rawQuery(
      'SELECT id, resource, lastUpdated FROM Medication WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      final oldResource = existingResource.first;
      await db.rawInsert('''
        INSERT INTO MedicationHistory (
          id, lastUpdated, resource
        ) VALUES (?, ?, ?);
      ''', [
        oldResource['id'],
        oldResource['lastUpdated'],
        oldResource['resource'],
      ]);
    }

    await db.rawInsert('''
    INSERT OR REPLACE INTO Medication (
      id, lastUpdated, resource, code, status, manufacturer, form
    ) VALUES (?, ?, ?, ?, ?, ?, ?);
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
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [Medication] by its ID
Future<Medication?> getMedication(Database db, String id) async {
  try {
    final result = await db.rawQuery(
      'SELECT resource FROM Medication WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return Medication.fromJsonString(result.first['resource']! as String);
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
