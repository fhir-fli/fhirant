import 'package:test/test.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:drift/native.dart';

void main() {
  group('FhirAntDb - Resource History', () {
    late FhirAntDb db;

    setUp(() async {
      db = FhirAntDb(NativeDatabase.memory());
      await db.initialize();
    });

    tearDown(() async {
      await db.close();
    });

    test('getResourceHistory returns versions in descending order', () async {
      // Save initial patient
      final patient1 = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'hist-1',
        'name': [
          {'family': 'First'},
        ],
      });
      await db.saveResource(patient1);

      await Future.delayed(const Duration(milliseconds: 1100));

      // Update with same ID, different name
      final patient2 = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'hist-1',
        'name': [
          {'family': 'Second'},
        ],
      });
      await db.saveResource(patient2);

      await Future.delayed(const Duration(milliseconds: 1100));

      // Update again with same ID, different name
      final patient3 = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'hist-1',
        'name': [
          {'family': 'Third'},
        ],
      });
      await db.saveResource(patient3);

      final history = await db.getResourceHistory(
        fhir.R4ResourceType.Patient,
        'hist-1',
      );

      expect(history.length, equals(3));

      // Verify descending order: first entry should have the latest lastUpdated
      final timestamps = history.map((r) => r.meta!.lastUpdated!).toList();
      for (int i = 0; i < timestamps.length - 1; i++) {
        expect(
          timestamps[i].valueDateTime!.isAfter(timestamps[i + 1].valueDateTime!),
          isTrue,
          reason:
              'Entry $i should have a later timestamp than entry ${i + 1}',
        );
      }
    });

    test('getResourceHistory returns empty for non-existent resource',
        () async {
      final history = await db.getResourceHistory(
        fhir.R4ResourceType.Patient,
        'non-existent-id',
      );

      expect(history, isEmpty);
    });

    test('getResourceHistory tracks distinct version IDs', () async {
      final patient1 = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'hist-2',
        'name': [
          {'family': 'VersionA'},
        ],
      });
      await db.saveResource(patient1);

      await Future.delayed(const Duration(milliseconds: 1100));

      final patient2 = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'hist-2',
        'name': [
          {'family': 'VersionB'},
        ],
      });
      await db.saveResource(patient2);

      await Future.delayed(const Duration(milliseconds: 1100));

      final patient3 = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'hist-2',
        'name': [
          {'family': 'VersionC'},
        ],
      });
      await db.saveResource(patient3);

      final history = await db.getResourceHistory(
        fhir.R4ResourceType.Patient,
        'hist-2',
      );

      expect(history.length, equals(3));

      final versionIds = history
          .map((r) => r.meta!.versionId!.valueString!)
          .toSet();
      expect(versionIds.length, equals(3),
          reason: 'All 3 version IDs should be distinct');
    });

    test('getResourceHistory contains both original and updated data',
        () async {
      final original = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'hist-3',
        'name': [
          {'family': 'Original'},
        ],
      });
      await db.saveResource(original);

      await Future.delayed(const Duration(milliseconds: 1100));

      final updated = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'hist-3',
        'name': [
          {'family': 'Updated'},
        ],
      });
      await db.saveResource(updated);

      final history = await db.getResourceHistory(
        fhir.R4ResourceType.Patient,
        'hist-3',
      );

      expect(history.length, equals(2));

      final familyNames = history
          .map((r) => (r as fhir.Patient).name!.first.family!.valueString!)
          .toList();
      expect(familyNames, contains('Original'));
      expect(familyNames, contains('Updated'));
    });

    test('delete does not remove history entries', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'hist-4',
        'name': [
          {'family': 'ToDelete'},
        ],
      });
      await db.saveResource(patient);

      // Verify the resource exists in the main table
      final before =
          await db.getResource(fhir.R4ResourceType.Patient, 'hist-4');
      expect(before, isNotNull);

      // Delete the resource from the main table
      final deleted =
          await db.deleteResource(fhir.R4ResourceType.Patient, 'hist-4');
      expect(deleted, isTrue);

      // Verify it is gone from the main table
      final after =
          await db.getResource(fhir.R4ResourceType.Patient, 'hist-4');
      expect(after, isNull);

      // Verify history entries are still present
      final history = await db.getResourceHistory(
        fhir.R4ResourceType.Patient,
        'hist-4',
      );
      expect(history, isNotEmpty);
      expect(history.length, equals(1));
    });
  });
}
