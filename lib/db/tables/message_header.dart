// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [MessageHeader] resources
void createMessageHeaderTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS MessageHeader (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''')
    ..execute('''
    CREATE TABLE IF NOT EXISTS MessageHeaderHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [MessageHeader] to the database
bool saveMessageHeader(Database db, MessageHeader resource) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true).newIdIfNoId() as MessageHeader;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated = updatedResource.meta?.lastUpdated?.valueDateTime;

  try {
    // Archive old version in the history table
    if (db.select('SELECT id FROM MessageHeader WHERE id = ?', [id]).isNotEmpty) {
      db.execute('''
        INSERT INTO MessageHeaderHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM MessageHeader WHERE id = ?;
      ''', [id]);
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO MessageHeader (
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

/// Get a [MessageHeader] by its ID
MessageHeader? getMessageHeader(Database db, String id) {
  try {
    final result = db.select('SELECT resource FROM MessageHeader WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return MessageHeader.fromJsonString(result.first['resource'] as String);
    }
  } catch (e) {
    print('Error retrieving resource: $e');
  }
  return null;
}
