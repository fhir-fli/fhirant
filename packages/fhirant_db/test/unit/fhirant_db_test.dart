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
        'name': [{'family': 'Doe', 'given': ['John']}],
      });

      final result = await db.saveResource(patient);

      expect(result, isTrue);
      expect(patient.id, isNotNull);
      expect(patient.meta, isNotNull);
      expect(patient.meta!.lastUpdated, isNotNull);
    });

    test('getResource retrieves a saved resource', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'name': [{'family': 'Smith', 'given': ['Jane']}],
      });

      await db.saveResource(patient);
      final id = patient.id!.valueString!;

      final retrieved = await db.getResource(fhir.R4ResourceType.Patient, id);

      expect(retrieved, isNotNull);
      expect(retrieved!.resourceTypeString, equals('Patient'));
      expect((retrieved as fhir.Patient).name?.first.family?.valueString, equals('Smith'));
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
        'name': [{'family': 'Original'}],
      });

      await db.saveResource(patient);
      final id = patient.id!.valueString!;
      final originalVersion = patient.meta!.versionId?.valueString;

      // Update the resource - create new patient with updated name
      final updatedPatient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': id,
        'name': [{'family': 'Updated'}],
      });
      await db.saveResource(updatedPatient);

      final retrieved = await db.getResource(fhir.R4ResourceType.Patient, id);
      expect(retrieved, isNotNull);
      final retrievedPatient = retrieved as fhir.Patient;
      expect(retrievedPatient.name?.first.family?.valueString, equals('Updated'));
      
      // Version should be updated
      expect(retrievedPatient.meta!.versionId?.valueString, isNot(equals(originalVersion)));
    });

    test('deleteResource removes a resource', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'name': [{'family': 'ToDelete'}],
      });

      await db.saveResource(patient);
      final id = patient.id!.valueString!;

      // Verify it exists
      final before = await db.getResource(fhir.R4ResourceType.Patient, id);
      expect(before, isNotNull);

      // Delete it
      final deleted = await db.deleteResource(fhir.R4ResourceType.Patient, id);
      expect(deleted, isTrue);

      // Verify it's gone
      final after = await db.getResource(fhir.R4ResourceType.Patient, id);
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
          'name': [{'family': 'Patient1'}],
        }),
        fhir.Patient.fromJson({
          'resourceType': 'Patient',
          'name': [{'family': 'Patient2'}],
        }),
        fhir.Patient.fromJson({
          'resourceType': 'Patient',
          'name': [{'family': 'Patient3'}],
        }),
      ];

      final result = await db.saveResources(patients);
      expect(result, isTrue);

      // Verify all were saved
      for (final patient in patients) {
        final id = patient.id!.valueString!;
        final retrieved = await db.getResource(fhir.R4ResourceType.Patient, id);
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
      // Create multiple patients
      for (int i = 0; i < 10; i++) {
        await db.saveResource(fhir.Patient.fromJson({
          'resourceType': 'Patient',
          'name': [{'family': 'Patient$i'}],
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
      expect(await db.getResourceCount(fhir.R4ResourceType.Patient), equals(0));

      // Add some resources
      for (int i = 0; i < 5; i++) {
        await db.saveResource(fhir.Patient.fromJson({
          'resourceType': 'Patient',
          'name': [{'family': 'Patient$i'}],
        }));
      }

      expect(await db.getResourceCount(fhir.R4ResourceType.Patient), equals(5));
    });

    test('getResourcesByType returns all resources of a type', () async {
      // Create mixed resources
      await db.saveResource(fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'name': [{'family': 'Patient1'}],
      }));
      await db.saveResource(fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'status': 'final',
      }));
      await db.saveResource(fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'name': [{'family': 'Patient2'}],
      }));

      final patients = await db.getResourcesByType(fhir.R4ResourceType.Patient);
      expect(patients.length, equals(2));
      expect(patients.every((r) => r.resourceTypeString == 'Patient'), isTrue);
    });
  });
}
