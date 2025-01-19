// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [AuditEvent] resources
void createAuditEventTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS AuditEvent (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS AuditEventHistory (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [AuditEvent] to the database
bool saveAuditEvent(Database db, AuditEvent resource) {
  final updatedResource =
      updateMeta(resource, versionIdAsTime: true).newIdIfNoId() as AuditEvent;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;

  try {
    // Archive old version in the history table
    if (db.select('SELECT id FROM AuditEvent WHERE id = ?', [id]).isNotEmpty) {
      db.execute(
        '''
        INSERT INTO AuditEventHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM AuditEvent WHERE id = ?;
      ''',
        [id],
      );
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO AuditEvent (
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

/// Get a [AuditEvent] by its ID
AuditEvent? getAuditEvent(Database db, String id) {
  try {
    final result =
        db.select('SELECT resource FROM AuditEvent WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return AuditEvent.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
