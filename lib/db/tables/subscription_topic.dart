// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqlite3/sqlite3.dart';

/// Create the primary and history tables for
/// [SubscriptionTopic] canonical resources
void createSubscriptionTopicTables(Database db) {
  db
    ..execute('''
    CREATE TABLE IF NOT EXISTS SubscriptionTopic (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date DATETIME,
      title TEXT,
      lastUpdated DATETIME NOT NULL
    );
  ''')
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_subscription_topic_url ON SubscriptionTopic (url);',
    )
    ..execute(
      'CREATE INDEX IF NOT EXISTS idx_subscription_topic_status ON SubscriptionTopic (status);',
    )
    ..execute('''
    CREATE TABLE IF NOT EXISTS SubscriptionTopicHistory (
      id TEXT PRIMARY KEY,
      lastUpdated DATETIME NOT NULL,
      resource TEXT NOT NULL
    );
  ''');
}

/// Save a [SubscriptionTopic] canonical resource to the database
bool saveSubscriptionTopic(Database db, SubscriptionTopic resource) {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as SubscriptionTopic;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated = updatedResource.meta?.lastUpdated?.valueDateTime;
  final url = updatedResource.url?.value;
  final status = updatedResource.status?.toString();
  final date = updatedResource.date?.valueDateTime;
  final title = updatedResource.title?.value;

  try {
    // Archive old version in the history table
    if (db.select(
      'SELECT id FROM SubscriptionTopic WHERE id = ?',
      [id],
    ).isNotEmpty) {
      db.execute(
        '''
        INSERT INTO SubscriptionTopicHistory (
          id, lastUpdated, resource
        ) SELECT id, lastUpdated, resource FROM SubscriptionTopic WHERE id = ?;
      ''',
        [id],
      );
    }

    // Insert new version into the main table
    db.execute('''
      INSERT INTO SubscriptionTopic (
        id, url, status, date, title, lastUpdated, resource
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        url = excluded.url,
        status = excluded.status,
        date = excluded.date,
        title = excluded.title,
        lastUpdated = excluded.lastUpdated,
        resource = excluded.resource;
    ''', [
      id,
      url,
      status,
      date,
      title,
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

/// Get a [SubscriptionTopic] canonical resource by its ID
SubscriptionTopic? getSubscriptionTopic(Database db, String id) {
  try {
    final result =
        db.select('SELECT resource FROM SubscriptionTopic WHERE id = ?', [id]);
    if (result.isNotEmpty) {
      return SubscriptionTopic.fromJsonString(
        result.first['resource'] as String,
      );
    }
  } catch (e) {
    // ignore: avoid_print
    print('Error retrieving resource: $e');
  }
  return null;
}
