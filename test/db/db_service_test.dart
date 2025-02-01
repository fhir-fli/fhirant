import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant/fhirant.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// Mock classes
class MockAppDatabase extends Mock implements AppDatabase {}

class MockGeneratedDatabase extends Mock implements GeneratedDatabase {}

// Create a mock for ResultSetImplementation
class MockResultSet extends Mock
    implements ResultSetImplementation<HasResultSet, dynamic> {}

void main() {
  late DbService dbService;
  late MockAppDatabase mockAppDatabase;

  setUp(() async {
    mockAppDatabase = MockAppDatabase();

    // Mock the attachedDatabase to return a valid GeneratedDatabase instance
    when(
      () => mockAppDatabase.attachedDatabase,
    ).thenReturn(MockGeneratedDatabase());

    dbService = DbService(); // Initialize DbService instance
    await dbService.initializeForTest(mockAppDatabase); // Set up mock database

    // Mock other database methods
    when(() => mockAppDatabase.close()).thenAnswer((_) async {});

    when(
      () => mockAppDatabase.saveResources(any()),
    ).thenAnswer((_) async => true);

    when(() => mockAppDatabase.select(mockAppDatabase.logs)).thenAnswer(
      (_) => SimpleSelectStatement<$LogsTable, Log>(
        mockAppDatabase.attachedDatabase,
        mockAppDatabase.logs,
      ),
    );

    when(
      () => mockAppDatabase.selectOnly<$LogsTable, Log>(mockAppDatabase.logs),
    ).thenReturn(
      JoinedSelectStatement<$LogsTable, Log>(
        mockAppDatabase.attachedDatabase, // The database connection
        mockAppDatabase.logs, // The table you want to query
        [], // Since no joins are being made, passing an empty list
      ),
    );
  });

  test('DbService initializes with a mock database', () async {
    // Act: Perform an operation that uses the database
    await dbService.insertLog(level: 'info', message: 'Test log');

    // Assert: Verify that the insertLog method interacts with the mock database
    verify(() => mockAppDatabase.into(mockAppDatabase.logs).insert(any()));
  });
}
