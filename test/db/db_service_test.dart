// ignore_for_file: subtype_of_sealed_class

import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhirant/fhirant.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// Mock database class
class MockAppDatabase extends Mock implements AppDatabase {}

// Mock table class for Patients
class MockPatientTable extends Mock implements $PatientTableTable {}

// Mock Drift row class
class MockPatientDrift extends Mock implements PatientDrift {}

// Mock Select Statement
class MockSelectStatement extends Mock
    implements SimpleSelectStatement<$PatientTableTable, PatientDrift> {}

void main() {
  late MockAppDatabase mockAppDatabase;
  late DbService dbService;
  late MockPatientTable mockPatientTable;
  late MockSelectStatement mockSelectStatement;

  setUp(() {
    mockAppDatabase = MockAppDatabase();
    dbService = DbService()..initializeForTest(mockAppDatabase);
    mockPatientTable = MockPatientTable();
    mockSelectStatement = MockSelectStatement();
  });

  test('getAllResourcesStrings returns list of resource strings', () async {
    const resourceType = R4ResourceType.Patient;

    // Mock `getTableByType` to return the correct patient table
    when(() => getTableByType(resourceType, mockAppDatabase))
        .thenReturn(mockPatientTable);

    // Mock `select()` to return a valid SimpleSelectStatement
    when(() => mockAppDatabase.select(mockPatientTable))
        .thenReturn(mockSelectStatement);

    // Create mock rows that match the table schema
    final mockRow1 = MockPatientDrift();
    when(mockRow1.toJson)
        .thenReturn({'resource': '{"resourceType": "Patient", "id": "123"}'});

    final mockRow2 = MockPatientDrift();
    when(mockRow2.toJson)
        .thenReturn({'resource': '{"resourceType": "Patient", "id": "456"}'});

    // Mock `.get()` to return the mocked rows
    when(() => mockSelectStatement.get())
        .thenAnswer((_) async => [mockRow1, mockRow2]);

    // Run the method
    final results = await dbService.getAllResourcesStrings(resourceType);

    // Check the output
    expect(results, isA<List<String>>());
    expect(results.length, 2);
    expect(results.first, '{"resourceType": "Patient", "id": "123"}');
  });
}
