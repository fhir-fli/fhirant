// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [Invoice] resources
void createInvoiceTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS Invoice (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS InvoiceHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [Invoice] to the database
bool saveInvoice(Database db, Invoice resource) {
  final updatedResource =
      updateMeta(resource, versionIdAsTime: true).newIdIfNoId() as Invoice;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
    final lastUpdated = updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;

  try {
    // Archive old version in the history table
    if (db.select('SELECT id FROM Invoice WHERE id = ?', [id]).isNotEmpty) {
      db.execute(
        '''
        INSERT INTO InvoiceHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM Invoice WHERE id = ?;
      ''',
        [id],
      );
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO Invoice (
        id, lastUpdated, resource
      ) VALUES (?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        lastUpdated = excluded.lastUpdated,
        resource = excluded.resource;
    ''', [
      id,
      lastUpdated,
      resourceJson,
    ]);

    return true;
  } catch (e) {
    // ignore: avoid_print
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [Invoice] by its ID
Invoice? getInvoice(Database db, String id) {
  try {
    final result = db.select('SELECT resource FROM Invoice WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return Invoice.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
