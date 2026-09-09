import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:test/test.dart';

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

      await Future<void>.delayed(const Duration(milliseconds: 1100));

      // Update with same ID, different name
      final patient2 = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'hist-1',
        'name': [
          {'family': 'Second'},
        ],
      });
      await db.saveResource(patient2);

      await Future<void>.delayed(const Duration(milliseconds: 1100));

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
      for (var i = 0; i < timestamps.length - 1; i++) {
        expect(
          timestamps[i]
              .valueDateTime!
              .isAfter(timestamps[i + 1].valueDateTime!),
          isTrue,
          reason: 'Entry $i should have a later timestamp than entry ${i + 1}',
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

      await Future<void>.delayed(const Duration(milliseconds: 1100));

      final patient2 = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'hist-2',
        'name': [
          {'family': 'VersionB'},
        ],
      });
      await db.saveResource(patient2);

      await Future<void>.delayed(const Duration(milliseconds: 1100));

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

      final versionIds =
          history.map((r) => r.meta!.versionId!.valueString!).toSet();
      expect(
        versionIds.length,
        equals(3),
        reason: 'All 3 version IDs should be distinct',
      );
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

      await Future<void>.delayed(const Duration(milliseconds: 1100));

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
      final after = await db.getResource(fhir.R4ResourceType.Patient, 'hist-4');
      expect(after, isNull);

      // The history keeps the original and the deletion tombstone. The
      // tombstone is an entry with no resource; the resource-only view
      // leaves it out rather than failing to parse it.
      final history = await db.getHistory(
        fhir.R4ResourceType.Patient,
        'hist-4',
      );
      expect(history.map((e) => e.deleted).toList(), [true, false]);
      expect(history.first.resource, isNull);
      expect(history.last.resource, isA<fhir.Patient>());
      expect(
        await db.getResourceHistory(fhir.R4ResourceType.Patient, 'hist-4'),
        hasLength(1),
      );
    });
  });
  group('schema 23: the current version is stored once', () {
    late FhirAntDb db;

    setUp(() async {
      db = FhirAntDb(NativeDatabase.memory());
      await db.initialize();
    });
    tearDown(() => db.close());

    fhir.Patient patient(String id, [String family = 'A']) =>
        fhir.Patient.fromJson({
          'resourceType': 'Patient',
          'id': id,
          'name': [
            {'family': family},
          ],
        });

    test(
        'type and system history list every version once, the current '
        'one from `resources`', () async {
      await db.saveResource(patient('h1'));
      await db.saveResource(patient('h1', 'B'));
      await db.saveResource(patient('h2'));
      await db.saveResource(
        fhir.Observation.fromJson({
          'resourceType': 'Observation',
          'id': 'o1',
          'status': 'final',
          'code': {
            'coding': [
              {'system': 'http://loinc.org', 'code': '8480-6'},
            ],
          },
          'subject': {'reference': 'Patient/h2'},
        }),
      );
      await db.deleteResource(fhir.R4ResourceType.Patient, 'h2');

      // The table holds only what a save replaced, plus tombstones.
      final rows = await db
          .customSelect(
            'SELECT id, version_id, deleted FROM resources_history '
            'ORDER BY id, version_id',
          )
          .get();
      expect(
        rows
            .map(
              (r) => '${r.read<String>('id')}/${r.read<String>('version_id')}'
                  '${r.read<bool>('deleted') ? '-tombstone' : ''}',
            )
            .toList(),
        ['h1/1', 'h2/1', 'h2/2-tombstone'],
      );

      // Type history: h1 v2 (current), h1 v1, h2 tombstone, h2 v1.
      final type = await db.getTypeHistory(fhir.R4ResourceType.Patient);
      expect(
        type.map((h) => '${h.id}/${h.versionId}${h.deleted ? '-t' : ''}'),
        unorderedEquals(['h1/2', 'h1/1', 'h2/2-t', 'h2/1']),
      );
      expect(await db.countTypeHistory(fhir.R4ResourceType.Patient), 4);
      expect(type.first.lastUpdated.isAfter(type.last.lastUpdated), isTrue);

      // System history adds the Observation's current version.
      expect(await db.countSystemHistory(), 5);
      final system = await db.getSystemHistory();
      expect(system.map((h) => h.id), contains('o1'));

      // Paging cuts the same ordered set.
      final page = await db.getSystemHistory(count: 2, offset: 1);
      expect(page, hasLength(2));
      expect(
        page.map((h) => '${h.id}/${h.versionId}'),
        system.sublist(1, 3).map((h) => '${h.id}/${h.versionId}'),
      );

      // `_at` before the update: h1 at version 1, from the history table.
      final beforeUpdate =
          (await db.getHistory(fhir.R4ResourceType.Patient, 'h1'))
              .last
              .lastUpdated;
      final at = await db.getTypeHistory(
        fhir.R4ResourceType.Patient,
        at: beforeUpdate,
      );
      expect(at.map((h) => '${h.id}/${h.versionId}'), ['h1/1']);

      // The compartment: h2's record, from both tables.
      final inH2 = await db.getSystemHistory(
        compartment: const CompartmentScope('Patient', 'h2'),
      );
      expect(
        inH2.map((h) => '${h.resourceType}/${h.id}/${h.versionId}'),
        unorderedEquals(['Patient/h2/2', 'Patient/h2/1', 'Observation/o1/1']),
      );
    });
  });
}
