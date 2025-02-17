import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  late AppDatabase testDb;
  late DbService dbService;

  setUp(() {
    // Create an in-memory version of your database.
    testDb = AppDatabase.forTesting(NativeDatabase.memory());
    // Instantiate DbService by passing in the test database.
    dbService = DbService(testDb);
  });

  tearDown(() async {
    await testDb.close();
  });

  test('insertLog should insert a log entry', () async {
    await dbService.insertLog(
      level: 'INFO',
      message: 'Test log message',
      method: 'GET',
      url: 'https://example.com',
    );

    final logs = await testDb.select(testDb.logs).get();
    expect(logs, isNotEmpty);
    expect(logs.first.message, equals('Test log message'));
  });

  test(
    'getAllResourcesStrings returns inserted account resource string',
    () async {
      // Prepare a test JSON string representing an Account resource.
      const resourceJson = '{"id": "acc1", "resourceType": "Account"}';

      // Insert directly into the account table using the generated companion.
      await testDb.into(testDb.accountTable).insert(
            AccountTableCompanion.insert(
              id: 'acc1',
              lastUpdated: DateTime.now().millisecondsSinceEpoch,
              resource: resourceJson,
            ),
          );

      // Call the service method.
      final result = await dbService.getAllResourcesStrings(
        R4ResourceType.Account,
      );

      expect(result, isNotEmpty);
      expect(result.first, equals(resourceJson));
    },
  );

  test('getAllResources returns valid FHIR resource objects', () async {
    // Prepare a test JSON string representing an Account resource.
    final resourceJson = jsonEncode({
      'resourceType': 'Account',
      'id': 'acc1',
      'status': 'active',
      'name': 'Test Account',
    });

    // Insert the test resource into the account table.
    await testDb.into(testDb.accountTable).insert(
          AccountTableCompanion.insert(
            id: 'acc1',
            lastUpdated: DateTime.now().millisecondsSinceEpoch,
            resource: resourceJson,
          ),
        );

    // Call the service method.
    final resources = await dbService.getAllResources(R4ResourceType.Account);

    expect(resources, isNotEmpty);
    // Check that the returned resource has the expected id.
    expect(resources.first.id?.value, equals('acc1'));
  });

  test('getResourcesWithPagination returns correct subset', () async {
    // Insert multiple fake Account resources.
    for (var i = 0; i < 5; i++) {
      final resourceJson = jsonEncode({
        'resourceType': 'Account',
        'id': 'acc$i',
        'status': 'active',
        'name': 'Test Account$i',
      });
      await testDb.into(testDb.accountTable).insert(
            AccountTableCompanion.insert(
              id: 'acc$i',
              lastUpdated: DateTime.now().millisecondsSinceEpoch,
              resource: resourceJson,
            ),
          );
    }

    // Request 2 records starting from offset 1.
    final pagedResources = await dbService.getResourcesWithPagination(
      resourceType: R4ResourceType.Account,
      count: 2,
      offset: 1,
    );

    expect(pagedResources.length, equals(2));
    // Optionally, check the ids of the returned resources.
    expect(pagedResources.first.id?.value, equals('acc1'));
  });

  test('getResource returns resource with specified ID', () async {
    final resourceJson = jsonEncode({
      'resourceType': 'Account',
      'id': 'acc123',
      'status': 'active',
      'name': 'Test Account',
    });
    // Insert the test resource.
    await testDb.into(testDb.accountTable).insert(
          AccountTableCompanion.insert(
            id: 'acc123',
            lastUpdated: DateTime.now().millisecondsSinceEpoch,
            resource: resourceJson,
          ),
        );

    final resource = await dbService.getResource(
      R4ResourceType.Account,
      'acc123',
    );
    expect(resource, isNotNull);
    expect(resource?.id?.value, equals('acc123'));
  });

  test('getResourceCount returns correct count', () async {
    // Insert three fake Account resources.
    for (var i = 0; i < 3; i++) {
      final resourceJson = jsonEncode({
        'resourceType': 'Account',
        'id': 'acc$i',
        'status': 'active',
        'name': 'Test Account$i',
      });
      await testDb.into(testDb.accountTable).insert(
            AccountTableCompanion.insert(
              id: 'acc$i',
              lastUpdated: DateTime.now().millisecondsSinceEpoch,
              resource: resourceJson,
            ),
          );
    }
    final count = await dbService.getResourceCount(R4ResourceType.Account);
    expect(count, equals(3));
  });

  test('exportResourcesToNDJSON successfully exports resources', () async {
    const resourceJson = '{"id": "acc1", "resourceType": "Account"}';
    await testDb.into(testDb.accountTable).insert(
          AccountTableCompanion.insert(
            id: 'acc1',
            lastUpdated: DateTime.now().millisecondsSinceEpoch,
            resource: resourceJson,
          ),
        );

    final tempFilePath = path.join(
      Directory.systemTemp.path,
      'export_test.tar.gz',
    );
    final result = await dbService.exportResourcesToNDJSON(
      R4ResourceType.Account,
      tempFilePath,
    );
    expect(result, isTrue);

    final exportedFile = File(tempFilePath);
    expect(exportedFile.existsSync(), isTrue);
    expect(exportedFile.lengthSync(), greaterThan(0));

    // Clean up.
    await exportedFile.delete();
  });

  test('saveResource inserts a resource successfully', () async {
    // Create a dummy FHIR Account resource.
    final account = Account(
      id: FhirString('accSave'),
      // Set any required fields here; if your model requires additional fields,
      // supply minimal valid values.
      name: 'Test Account'.toFhirString,
      status: AccountStatus.active,
    );

    final result = await dbService.saveResource(account);
    expect(result, isTrue);

    // Verify that the resource now exists in the account table.
    final insertedResource = await dbService.getResource(
      R4ResourceType.Account,
      'accSave',
    );
    expect(insertedResource, isNotNull);
  });

  test('getValidResourceTypes returns resource types with data', () async {
    const resourceJson = '{"id": "acc1", "resourceType": "Account"}';
    await testDb.into(testDb.accountTable).insert(
          AccountTableCompanion.insert(
            id: 'acc1',
            lastUpdated: DateTime.now().millisecondsSinceEpoch,
            resource: resourceJson,
          ),
        );

    final validTypes = await dbService.getValidResourceTypes();
    expect(validTypes, contains(R4ResourceType.Account));
  });
}
