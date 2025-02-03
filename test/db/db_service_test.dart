import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant/fhirant.dart';
import 'package:flutter_test/flutter_test.dart';

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
      await testDb
          .into(testDb.accountTable)
          .insert(
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
}
