import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [MedicationRequest] resources
Future<void> createMedicationRequestTables(Transaction txn) async {
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS MedicationRequest (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      patientId TEXT NOT NULL,
      medicationId TEXT NOT NULL,
      intent TEXT,
      priority TEXT,
      status TEXT
    );
  ''');
  await txn.execute(
    'CREATE INDEX IF NOT EXISTS idx_medication_request_patientId ON MedicationRequest (patientId);',
  );
  await txn.execute(
    'CREATE INDEX IF NOT EXISTS idx_medication_request_status ON MedicationRequest (status);',
  );
  await txn.execute('''
    CREATE TABLE IF NOT EXISTS MedicationRequestHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [MedicationRequest] to the database
Future<bool> saveMedicationRequest(
  Transaction txn,
  MedicationRequest medicationRequest,
) async {
  final updatedRequest =
      updateMeta(medicationRequest, versionIdAsTime: true).newIdIfNoId();
  final id = updatedRequest.id?.value;
  final resourceJson = updatedRequest.toJsonString();
  final lastUpdated =
      updatedRequest.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final patientId = medicationRequest.subject.reference?.value;
  final medicationId = medicationRequest.medicationX
          .isAs<CodeableConcept>()
          ?.coding
          ?.first
          .code
          ?.value ??
      medicationRequest.medicationX
          .isAs<Reference>()
          ?.reference
          ?.value
          ?.split('/')
          .last;
  final intent = medicationRequest.intent.toString();
  final priority = medicationRequest.priority?.toString();
  final status = medicationRequest.status.toString();

  try {
    final existingResource = await txn.rawQuery(
      'SELECT id, resource, lastUpdated FROM MedicationRequest WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      final oldResource = existingResource.first;
      await txn.rawInsert('''
        INSERT INTO MedicationRequestHistory (
          id, lastUpdated, resource
        ) VALUES (?, ?, ?);
      ''', [
        oldResource['id'],
        oldResource['lastUpdated'],
        oldResource['resource'],
      ]);
    }

    await txn.rawInsert('''
    INSERT OR REPLACE INTO MedicationRequest (
      id, lastUpdated, resource, patientId, medicationId, intent, priority, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
  ''', [
      id,
      lastUpdated,
      resourceJson,
      patientId,
      medicationId,
      intent,
      priority,
      status,
    ]);
    return true;
  } catch (e) {
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [MedicationRequest] by its ID
Future<MedicationRequest?> getMedicationRequest(
  Transaction txn,
  String id,
) async {
  try {
    final result = await txn.rawQuery(
      'SELECT resource FROM MedicationRequest WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return MedicationRequest.fromJsonString(
        result.first['resource']! as String,
      );
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
