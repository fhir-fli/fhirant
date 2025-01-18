// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [PaymentNotice] resources
void createPaymentNoticeTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS PaymentNotice (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS PaymentNoticeHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [PaymentNotice] to the database
bool savePaymentNotice(Database db, PaymentNotice resource) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true).newIdIfNoId() as PaymentNotice;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated = updatedResource.meta?.lastUpdated?.valueDateTime;

  try {
    // Archive old version in the history table
    if (db.select('SELECT id FROM PaymentNotice WHERE id = ?', [id]).isNotEmpty) {
      db.execute('''
        INSERT INTO PaymentNoticeHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM PaymentNotice WHERE id = ?;
      ''', [id]);
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO PaymentNotice (
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
    print('Error saving resource: $e');
    return false;
  }
}

/// Get a [PaymentNotice] by its ID
PaymentNotice? getPaymentNotice(Database db, String id) {
  try {
    final result = db.select('SELECT resource FROM PaymentNotice WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return PaymentNotice.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
