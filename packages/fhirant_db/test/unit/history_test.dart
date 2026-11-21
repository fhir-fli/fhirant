import 'dart:io';

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
  group('schema 30: history pages in one total order', () {
    late FhirAntDb db;

    setUp(() async {
      db = FhirAntDb(NativeDatabase.memory());
      await db.initialize();
    });

    tearDown(() async => db.close());

    test('a schema-29 store gains the history order indexes', () async {
      final dir = await Directory.systemTemp.createTemp('fhirant_db_hist_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/fhirant.sqlite');
      final first = FhirAntDb(NativeDatabase(file));
      await first.saveResource(fhir.Patient(id: 'a'.toFhirString));
      await first.customStatement('DROP INDEX idx_resources_history_order');
      await first.customStatement('DROP INDEX idx_resources_order');
      await first.customStatement('PRAGMA user_version = 29');
      await first.close();

      final second = FhirAntDb(NativeDatabase(file));
      final plan = await second
          .customSelect(
            'EXPLAIN QUERY PLAN SELECT rowid FROM resources '
            'ORDER BY last_updated DESC, version_id DESC, '
            'resource_type DESC, id DESC',
          )
          .get();
      expect(
        plan.map((r) => r.read<String>('detail')).join('; '),
        contains('idx_resources_order'),
      );
      final indexes = (await second
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'index'",
              )
              .get())
          .map((r) => r.read<String>('name'));
      expect(
        indexes,
        containsAll(['idx_resources_history_order', 'idx_resources_order']),
      );
      await second.close();
    });

    test(
        'versions sharing a millisecond and a version id are paged in type '
        'and id order, none repeated or skipped', () async {
      // One call, so most share a millisecond; each a first version.
      await db.saveResources([
        for (var i = 0; i < 12; i++)
          fhir.Patient(id: 'p${i.toString().padLeft(2, '0')}'.toFhirString),
        for (var i = 0; i < 8; i++) fhir.Organization(id: 'o$i'.toFhirString),
      ]);
      // An update, so a page draws from both halves of the versions.
      await db.saveResource(
        fhir.Patient(id: 'p03'.toFhirString, active: true.toFhirBoolean),
      );

      for (final type in [null, 'Patient']) {
        final paged = <HistoryEntry>[];
        for (var offset = 0;; offset += 3) {
          final page = type == null
              ? await db.getSystemHistory(count: 3, offset: offset)
              : await db.getTypeHistory(
                  fhir.R4ResourceType.Patient,
                  count: 3,
                  offset: offset,
                );
          if (page.isEmpty) break;
          paged.addAll(page);
        }
        final all = type == null
            ? await db.getSystemHistory()
            : await db.getTypeHistory(fhir.R4ResourceType.Patient);
        String key(HistoryEntry e) =>
            '${e.resourceType}/${e.id}/${e.versionId}';
        final expected = [...all]..sort((a, b) {
            final byTime = b.lastUpdated.compareTo(a.lastUpdated);
            if (byTime != 0) return byTime;
            final byVersion = b.versionId.compareTo(a.versionId);
            if (byVersion != 0) return byVersion;
            final byType = b.resourceType.compareTo(a.resourceType);
            if (byType != 0) return byType;
            return b.id.compareTo(a.id);
          });
        expect(paged.map(key).toList(), expected.map(key).toList());
        expect(paged.map(key).toSet(), hasLength(type == null ? 21 : 13));

        // The same pages by position: each starts after the last row of
        // the one before.
        final byPosition = <HistoryEntry>[];
        HistoryPosition? after;
        for (;;) {
          final page = type == null
              ? await db.getSystemHistory(count: 3, after: after)
              : await db.getTypeHistory(
                  fhir.R4ResourceType.Patient,
                  count: 3,
                  after: after,
                );
          if (page.isEmpty) break;
          byPosition.addAll(page);
          after = HistoryPosition.of(page.last);
        }
        expect(byPosition.map(key).toList(), expected.map(key).toList());
      }
    });

    test('a position pages with _since, and not with _at or an offset',
        () async {
      await db.saveResource(fhir.Patient(id: 'old'.toFhirString));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final since = DateTime.now().toUtc();
      await db.saveResources([
        for (var i = 0; i < 5; i++) fhir.Patient(id: 'new$i'.toFhirString),
      ]);
      final first = await db.getSystemHistory(since: since, count: 2);
      final rest = await db.getSystemHistory(
        since: since,
        after: HistoryPosition.of(first.last),
      );
      expect(
        [...first, ...rest].map((e) => e.id).toSet(),
        {for (var i = 0; i < 5; i++) 'new$i'},
      );
      expect(first.length + rest.length, 5);
      final position = HistoryPosition.of(first.last);
      expect(
        () => db.getSystemHistory(at: since, after: position),
        throwsArgumentError,
      );
      expect(
        () => db.getSystemHistory(offset: 2, after: position),
        throwsArgumentError,
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
