import 'package:flutter_test/flutter_test.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:drift/native.dart';

void main() {
  group('FhirAntDb - CRUD Operations', () {
    late FhirAntDb db;

    setUp(() async {
      // Use in-memory database for testing
      db = FhirAntDb.forTesting(NativeDatabase.memory());
      await db.initialize();
    });

    tearDown(() async {
      await db.close();
    });

    test('saveResource creates a new resource with ID', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'test-1',
        'name': [
          {
            'family': 'Doe',
            'given': ['John'],
          }
        ],
      });

      final result = await db.saveResource(patient);

      expect(result, isTrue);

      // Verify the resource was saved and can be retrieved
      final retrieved =
          await db.getResource(fhir.R4ResourceType.Patient, 'test-1');
      expect(retrieved, isNotNull);
      expect(retrieved!.id, isNotNull);
      expect(retrieved.meta, isNotNull);
      expect(retrieved.meta!.lastUpdated, isNotNull);
    });

    test('getResource retrieves a saved resource', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'test-2',
        'name': [
          {
            'family': 'Smith',
            'given': ['Jane'],
          }
        ],
      });

      await db.saveResource(patient);

      final retrieved =
          await db.getResource(fhir.R4ResourceType.Patient, 'test-2');

      expect(retrieved, isNotNull);
      expect(retrieved!.resourceTypeString, equals('Patient'));
      expect((retrieved as fhir.Patient).name?.first.family?.valueString,
          equals('Smith'));
    });

    test('getResource returns null for non-existent resource', () async {
      final retrieved = await db.getResource(
        fhir.R4ResourceType.Patient,
        'non-existent-id',
      );

      expect(retrieved, isNull);
    });

    test('saveResource updates existing resource', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'test-3',
        'name': [
          {'family': 'Original'}
        ],
      });

      await db.saveResource(patient);

      // Retrieve the original to get its version
      final original =
          await db.getResource(fhir.R4ResourceType.Patient, 'test-3');
      expect(original, isNotNull);
      final originalVersion = original!.meta!.versionId?.valueString;

      // Update the resource - create new patient with updated name but same ID
      final updatedPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'test-3',
        'name': [
          {'family': 'Updated'}
        ],
      });
      await db.saveResource(updatedPatient);

      final retrieved =
          await db.getResource(fhir.R4ResourceType.Patient, 'test-3');
      expect(retrieved, isNotNull);
      final retrievedPatient = retrieved as fhir.Patient;
      expect(
          retrievedPatient.name?.first.family?.valueString, equals('Updated'));

      // Version should be updated
      expect(retrievedPatient.meta!.versionId?.valueString,
          isNot(equals(originalVersion)));
    });

    test('deleteResource removes a resource', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'test-4',
        'name': [
          {'family': 'ToDelete'}
        ],
      });

      await db.saveResource(patient);

      // Verify it exists
      final before =
          await db.getResource(fhir.R4ResourceType.Patient, 'test-4');
      expect(before, isNotNull);

      // Delete it
      final deleted =
          await db.deleteResource(fhir.R4ResourceType.Patient, 'test-4');
      expect(deleted, isTrue);

      // Verify it's gone
      final after =
          await db.getResource(fhir.R4ResourceType.Patient, 'test-4');
      expect(after, isNull);
    });

    test('deleteResource returns false for non-existent resource', () async {
      final result = await db.deleteResource(
        fhir.R4ResourceType.Patient,
        'non-existent-id',
      );

      expect(result, isFalse);
    });

    test('saveResources saves multiple resources', () async {
      final patients = [
        fhir.Patient.fromJson({
          'resourceType': 'Patient',
          'id': 'batch-1',
          'name': [
            {'family': 'Patient1'}
          ],
        }),
        fhir.Patient.fromJson({
          'resourceType': 'Patient',
          'id': 'batch-2',
          'name': [
            {'family': 'Patient2'}
          ],
        }),
        fhir.Patient.fromJson({
          'resourceType': 'Patient',
          'id': 'batch-3',
          'name': [
            {'family': 'Patient3'}
          ],
        }),
      ];

      final result = await db.saveResources(patients);
      expect(result, isTrue);

      // Verify all were saved using the known IDs
      for (final id in ['batch-1', 'batch-2', 'batch-3']) {
        final retrieved =
            await db.getResource(fhir.R4ResourceType.Patient, id);
        expect(retrieved, isNotNull);
      }
    });
  });

  group('FhirAntDb - Query Operations', () {
    late FhirAntDb db;

    setUp(() async {
      db = FhirAntDb.forTesting(NativeDatabase.memory());
      await db.initialize();
    });

    tearDown(() async {
      await db.close();
    });

    test('getResourcesWithPagination returns paginated results', () async {
      // Create multiple patients with known IDs
      for (int i = 0; i < 10; i++) {
        await db.saveResource(fhir.Patient.fromJson({
          'resourceType': 'Patient',
          'id': 'page-$i',
          'name': [
            {'family': 'Patient$i'}
          ],
        }));
      }

      final firstPage = await db.getResourcesWithPagination(
        resourceType: fhir.R4ResourceType.Patient,
        count: 5,
        offset: 0,
      );

      expect(firstPage.length, equals(5));

      final secondPage = await db.getResourcesWithPagination(
        resourceType: fhir.R4ResourceType.Patient,
        count: 5,
        offset: 5,
      );

      expect(secondPage.length, equals(5));

      // Verify no overlap
      final firstIds = firstPage.map((r) => r.id!.valueString!).toSet();
      final secondIds = secondPage.map((r) => r.id!.valueString!).toSet();
      expect(firstIds.intersection(secondIds), isEmpty);
    });

    test('getResourceCount returns correct count', () async {
      // Initially should be 0
      expect(
          await db.getResourceCount(fhir.R4ResourceType.Patient), equals(0));

      // Add some resources
      for (int i = 0; i < 5; i++) {
        await db.saveResource(fhir.Patient.fromJson({
          'resourceType': 'Patient',
          'id': 'count-$i',
          'name': [
            {'family': 'Patient$i'}
          ],
        }));
      }

      expect(
          await db.getResourceCount(fhir.R4ResourceType.Patient), equals(5));
    });

    test('getResourcesByType returns all resources of a type', () async {
      // Create mixed resources
      await db.saveResource(fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'type-patient-1',
        'name': [
          {'family': 'Patient1'}
        ],
      }));
      await db.saveResource(fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': 'type-obs-1',
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '12345-6'}
          ]
        },
      }));
      await db.saveResource(fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'type-patient-2',
        'name': [
          {'family': 'Patient2'}
        ],
      }));

      final patients =
          await db.getResourcesByType(fhir.R4ResourceType.Patient);
      expect(patients.length, equals(2));
      expect(
          patients.every((r) => r.resourceTypeString == 'Patient'), isTrue);
    });
  });

  group('FhirAntDb - Additional Operations', () {
    late FhirAntDb db;

    setUp(() async {
      db = FhirAntDb.forTesting(NativeDatabase.memory());
      await db.initialize();
    });

    tearDown(() async {
      await db.close();
    });

    test('getResourceTypes returns distinct types', () async {
      // Save a Patient and an Observation
      await db.saveResource(fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'types-patient-1',
        'name': [
          {'family': 'Doe'}
        ],
      }));
      await db.saveResource(fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': 'types-obs-1',
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '12345-6'}
          ]
        },
      }));

      final types = await db.getResourceTypes();

      expect(types.length, equals(2));
      expect(types, contains(fhir.R4ResourceType.Patient));
      expect(types, contains(fhir.R4ResourceType.Observation));
    });

    test('getResourceTypes returns empty when no resources', () async {
      final types = await db.getResourceTypes();

      expect(types, isEmpty);
    });

    test('clear removes all resources', () async {
      // Save some resources
      await db.saveResource(fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'clear-patient-1',
        'name': [
          {'family': 'Doe'}
        ],
      }));
      await db.saveResource(fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'clear-patient-2',
        'name': [
          {'family': 'Smith'}
        ],
      }));
      await db.saveResource(fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': 'clear-obs-1',
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '12345-6'}
          ]
        },
      }));

      // Verify resources exist
      expect(await db.getResourceCount(fhir.R4ResourceType.Patient), equals(2));
      expect(
          await db.getResourceCount(fhir.R4ResourceType.Observation), equals(1));

      // Clear the database
      await db.clear();

      // Verify all resources are gone
      expect(await db.getResourceCount(fhir.R4ResourceType.Patient), equals(0));
      expect(
          await db.getResourceCount(fhir.R4ResourceType.Observation), equals(0));
    });

    test('clear does not throw and resources are gone', () async {
      // Save a resource
      await db.saveResource(fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'clear-nothrow-1',
        'name': [
          {'family': 'TestClear'}
        ],
      }));

      // Verify resource exists
      final before =
          await db.getResource(fhir.R4ResourceType.Patient, 'clear-nothrow-1');
      expect(before, isNotNull);

      // Clear should not throw
      await expectLater(db.clear(), completes);

      // Verify resources are gone
      final after =
          await db.getResource(fhir.R4ResourceType.Patient, 'clear-nothrow-1');
      expect(after, isNull);

      // Verify resource types list is empty
      final types = await db.getResourceTypes();
      expect(types, isEmpty);
    });

    test('searchCount with no params returns total count', () async {
      // Save 3 patients
      await db.saveResource(fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'search-count-1',
        'name': [
          {'family': 'Alpha'}
        ],
      }));
      await db.saveResource(fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'search-count-2',
        'name': [
          {'family': 'Beta'}
        ],
      }));
      await db.saveResource(fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'search-count-3',
        'name': [
          {'family': 'Gamma'}
        ],
      }));

      final count = await db.searchCount(
        resourceType: fhir.R4ResourceType.Patient,
      );

      expect(count, equals(3));
    });
  });
}
