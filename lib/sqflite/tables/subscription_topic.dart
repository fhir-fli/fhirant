// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

/// Create the primary and history tables for
/// [SubscriptionTopic] canonical resources
Future<void> createSubscriptionTopicTables(Database db)  async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS SubscriptionTopic (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date INT,
      title TEXT,
      lastUpdated INT NOT NULL
    );
  ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_subscription_topic_url ON SubscriptionTopic (url);',
    )
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_subscription_topic_status ON SubscriptionTopic (status);',
    )
    await db.execute('''
    CREATE TABLE IF NOT EXISTS SubscriptionTopicHistory (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    );
  ''');
}

/// Save a [SubscriptionTopic] canonical resource to the database
Future<bool> saveSubscriptionTopic(
  Database db,
  SubscriptionTopic resource,
) async {
  final updatedResource = updateMeta(resource, versionIdAsTime: true)
      .newIdIfNoId() as SubscriptionTopic;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final url = updatedResource.url?.value;
  final status = updatedResource.status?.toString();
  final date = updatedResource.date?.valueDateTime?.millisecondsSinceEpoch;
  final title = updatedResource.title?.value;

  try {
    // Check if a resource with the same ID exists
    final existingResource = db.select(
      'SELECT id, resource, lastUpdated FROM SubscriptionTopic WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      // Insert the current version into the history table before updating
      final oldResource = existingResource.first;
      await db.execute('''
        INSERT INTO SubscriptionTopicHistory (
          id, lastUpdated, resource
        ) VALUES (?, ?, ?);
      ''', [
        oldResource['id'],
        oldResource['lastUpdated'],
        oldResource['resource'],
      ]);
    }

    // Insert new version into the main table
    await db.execute('''
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
    final result = db.select(
      'SELECT resource FROM SubscriptionTopic WHERE id = ?',
      [id],
    );
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
