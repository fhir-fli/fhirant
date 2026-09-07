import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:test/test.dart';

/// Schema 14 rebuilds the search index from the stored resources.
///
/// fhir_r4_db's schema 7 changed how every parameter type is extracted, and
/// its own migration for anything older is `rebuildSearchIndex()`. fhirant
/// overrides `migration`, so the package's upgrade never runs here and the
/// call has to be made from fhirant's own step. This test proves it is: a
/// database whose index rows are gone and whose version says 13 is searchable
/// again after being reopened.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fhirant_db_upgrade_');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('opening a schema-13 database re-extracts every index row', () async {
    final file = File('${dir.path}/fhirant.sqlite');

    // Build a database at the current schema with one indexed Patient, then
    // make it look like a 13 whose index predates the extractor: index rows
    // gone, version stamped 13.
    final first = FhirAntDb(NativeDatabase(file));
    await first.saveResource(
      fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'upgrade-1',
        'name': [
          {'family': 'Rebuilt', 'given': <String>['Index']},
        ],
        'birthDate': '1980-02-03',
      }),
    );
    expect(
      (await first.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {'family': <String>['Rebuilt']},
      ))
          .length,
      1,
    );
    await first.customStatement('DELETE FROM string_search_parameters');
    await first.customStatement('DELETE FROM date_search_parameters');
    await first.customStatement('DELETE FROM sqlite_stat1');
    await first.customStatement('PRAGMA user_version = 13');
    await first.close();

    // A fresh open sees 13 < 14 and runs the step.
    final second = FhirAntDb(NativeDatabase(file));
    final byName = await second.search(
      resourceType: fhir.R4ResourceType.Patient,
      searchParameters: {'family': <String>['Rebuilt']},
    );
    expect(byName.map((r) => r.id.toString()), equals(['upgrade-1']));

    final byDate = await second.search(
      resourceType: fhir.R4ResourceType.Patient,
      searchParameters: {'birthdate': <String>['1980-02-03']},
    );
    expect(byDate.map((r) => r.id.toString()), equals(['upgrade-1']));

    // The value indexes and planner statistics were rebuilt with it.
    final indexes = await second
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name LIKE 'idx_%'",
        )
        .get();
    expect(
      indexes.map((r) => r.read<String>('name')),
      containsAll(<String>[
        'idx_string_value',
        'idx_date_value',
        'idx_date_value_end',
        'idx_quantity_low',
        'idx_token_search_parameters_contained',
      ]),
    );
    final stats = await second
        .customSelect('SELECT COUNT(*) AS c FROM sqlite_stat1')
        .get();
    expect(stats.first.read<int>('c'), greaterThan(0));

    final version =
        await second.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 15);
    await second.close();
  });
}
