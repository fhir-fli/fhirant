import 'dart:io';
import 'package:fhir_r4/fhir_r4.dart';

void main() {
  for (final resource in R4ResourceType.typesAsStrings) {
    var fileString = '''
// ignore_for_file: lines_longer_than_80_chars

import 'package:fhir_r4/fhir_r4.dart';
import 'package:sqflite/sqflite.dart';

''';

    if (![
      'Condition',
      'Encounter',
      'Location',
      'MedicationAdministration',
      'MedicationDispense',
      'MedicationRequest',
      'Medication',
      'Observation',
      'Patient',
      'Procedure',
      'Specimen',
    ].contains(resource)) {
      if (resource.isCanonicalResource) {
        if (['Endpoint', 'Group', 'List'].contains(resource)) {
          fileString += canonicalTableCreate('Fhir$resource');
        } else {
          fileString += canonicalTableCreate(resource);
        }
      } else {
        if (['Endpoint', 'Group', 'List'].contains(resource)) {
          fileString += baseTableCreate('Fhir$resource');
        } else {
          fileString += baseTableCreate(resource);
        }
      }

      final fileName = resource.toLowerSnakeCase();
      File('tables/$fileName.dart').writeAsStringSync(fileString);
    }
  }
}

/// Create the primary table for the resourceType resources
String baseTableCreate(String resourceType) => """
/// Create the primary and history tables for
/// [$resourceType] resources
Future<void> create${resourceType}Tables(Transaction txn) async {
  await txn.execute(
    '''
    CREATE TABLE IF NOT EXISTS $resourceType (
      id TEXT PRIMARY KEY,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL
    )
    '''
  );
  await txn.execute(
    '''
    CREATE TABLE IF NOT EXISTS ${resourceType}History (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    )
    '''
  );
}

/// Save a [$resourceType] to the database
Future<bool> save$resourceType(Transaction txn, $resourceType resource) async {
  final updatedResource =
      updateMeta(resource, versionIdAsTime: true).newIdIfNoId() as $resourceType;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;

  try {
    final existingResource = await txn.rawQuery(
      'SELECT id, resource, lastUpdated FROM $resourceType WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      final oldResource = existingResource.first;
      await txn.rawInsert(
        '''
        INSERT INTO ${resourceType}History (
          id, lastUpdated, resource
        ) VALUES (?, ?, ?)
        ''',
        [
          oldResource['id'],
          oldResource['lastUpdated'],
          oldResource['resource'],
        ],
      );
    }

    await txn.rawInsert(
      '''
      INSERT OR REPLACE INTO $resourceType (
        id, lastUpdated, resource
      ) VALUES (?, ?, ?)
      ''',
      [
        id,
        lastUpdated,
        resourceJson,
      ],
    );

    return true;
  } catch (e) {
    print('Error saving resource: \$e');
    return false;
  }
}

/// Get a [$resourceType] by its ID
Future<$resourceType?> get$resourceType(Transaction txn, String id) async {
  try {
    final result = await txn.rawQuery(
      'SELECT resource FROM $resourceType WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return $resourceType.fromJsonString(
        result.first['resource'] as String,
      );
    }
  } catch (e) {
    print('Error retrieving resource: \$e');
  }
  return null;
}
""";

/// Create the primary and history tables for
String canonicalTableCreate(String resourceType) => """
/// Create the primary and history tables for
/// [$resourceType] canonical resources
Future<void> create${resourceType}Tables(Transaction txn) async {
  await txn.execute(
    '''
    CREATE TABLE IF NOT EXISTS $resourceType (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      status TEXT NOT NULL,
      date INT,
      title TEXT,
      lastUpdated INT NOT NULL
    )
    '''
  );
  await txn.execute(
    '''
    CREATE INDEX IF NOT EXISTS idx_${resourceType.toLowerSnakeCase()}_url
    ON $resourceType (url)
    '''
  );
  await txn.execute(
    '''
    CREATE INDEX IF NOT EXISTS idx_${resourceType.toLowerSnakeCase()}_status
    ON $resourceType (status)
    '''
  );
  await txn.execute(
    '''
    CREATE TABLE IF NOT EXISTS ${resourceType}History (
      id TEXT NOT NULL,
      lastUpdated INT NOT NULL,
      resource TEXT NOT NULL,
      PRIMARY KEY (id, lastUpdated)
    )
    '''
  );
}

/// Save a [$resourceType] canonical resource to the database
Future<bool> save$resourceType(Transaction txn, $resourceType resource) async {
  final updatedResource =
      updateMeta(resource, versionIdAsTime: true).newIdIfNoId() as $resourceType;
  final id = updatedResource.id?.value;
  final resourceJson = updatedResource.toJsonString();
  final lastUpdated =
      updatedResource.meta?.lastUpdated?.valueDateTime?.millisecondsSinceEpoch;
  final url = updatedResource.url?.value;
  final status = updatedResource.status?.toString();
  final date = updatedResource.date?.valueDateTime?.millisecondsSinceEpoch;
  final title = updatedResource.title?.value;

  try {
    final existingResource = await txn.rawQuery(
      'SELECT id, resource, lastUpdated FROM $resourceType WHERE id = ?',
      [id],
    );

    if (existingResource.isNotEmpty) {
      final oldResource = existingResource.first;
      await txn.rawInsert(
        '''
        INSERT INTO ${resourceType}History (
          id, lastUpdated, resource
        ) VALUES (?, ?, ?)
        ''',
        [
          oldResource['id'],
          oldResource['lastUpdated'],
          oldResource['resource'],
        ],
      );
    }

    await txn.rawInsert(
      '''
      INSERT OR REPLACE INTO $resourceType (
        id, url, status, date, title, lastUpdated, resource
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        id,
        url,
        status,
        date,
        title,
        lastUpdated,
        resourceJson,
      ],
    );

    return true;
  } catch (e) {
    print('Error saving resource: \$e');
    return false;
  }
}

/// Get a [$resourceType] canonical resource by its ID
Future<$resourceType?> get$resourceType(Transaction txn, String id) async {
  try {
    final result = await txn.rawQuery(
      'SELECT resource FROM $resourceType WHERE id = ?',
      [id],
    );
    if (result.isNotEmpty) {
      return $resourceType.fromJsonString(
        result.first['resource'] as String,
      );
    }
  } catch (e) {
    print('Error retrieving resource: \$e');
  }
  return null;
}
""";
