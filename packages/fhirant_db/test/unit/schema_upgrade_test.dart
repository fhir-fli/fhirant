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
          {
            'family': 'Rebuilt',
            'given': <String>['Index'],
          },
        ],
        'birthDate': '1980-02-03',
      }),
    );
    expect(
      (await first.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'family': <String>['Rebuilt'],
        },
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
      searchParameters: {
        'family': <String>['Rebuilt'],
      },
    );
    expect(byName.map((r) => r.id.toString()), equals(['upgrade-1']));

    final byDate = await second.search(
      resourceType: fhir.R4ResourceType.Patient,
      searchParameters: {
        'birthdate': <String>['1980-02-03'],
      },
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
        'idx_string_search_parameters_value_cover',
        'idx_date_search_parameters_low_cover',
        'idx_date_search_parameters_high_cover',
        'idx_quantity_search_parameters_low_cover',
        'idx_token_search_parameters_owner',
        'idx_token_search_parameters_contained',
        'idx_resources_type_updated',
      ]),
    );
    final stats = await second
        .customSelect('SELECT COUNT(*) AS c FROM sqlite_stat1')
        .get();
    expect(stats.first.read<int>('c'), greaterThan(0));

    final version =
        await second.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), second.schemaVersion);
    await second.close();
  });

  test(
      'opening a schema-15 database gains users.patient_id and the '
      'oauth_clients pin table', () async {
    final file = File('${dir.path}/fhirant.sqlite');
    final first = FhirAntDb(NativeDatabase(file));
    await first.createUser(
      username: 'before',
      passwordHash: 'h',
      salt: 's',
    );
    // Make it look like a 15: drop what 16 adds, stamp the version.
    await first.customStatement('DROP TABLE oauth_clients');
    await first.customStatement('ALTER TABLE users DROP COLUMN patient_id');
    await first.customStatement('PRAGMA user_version = 15');
    await first.close();

    final second = FhirAntDb(NativeDatabase(file));
    final id = await second.createUser(
      username: 'after',
      passwordHash: 'h',
      salt: 's',
      patientId: 'pat-1',
    );
    expect((await second.getUserById(id))!.patientId, 'pat-1');
    expect((await second.getUserByUsername('before'))!.patientId, isNull);

    await second.registerOAuthClient('app', 'http://app/cb');
    await second.registerOAuthClient('app', 'http://other/cb');
    expect(await second.getOAuthClientRedirect('app'), 'http://app/cb');
    await second.deleteOAuthClient('app');
    expect(await second.getOAuthClientRedirect('app'), isNull);
    await second.close();
  });

  test('opening a schema-16 database rebuilds the search index', () async {
    // fhir_r4_db schema 9 (fhirant 17): the string index rows of Address
    // and ContactPoint values moved onto the whole-value convention `_sort`
    // uses, so the index is re-extracted. Observable: the string rows are
    // emptied by hand, the version stamped back to 16, and the reopen
    // brings them back on the new numbers.
    final file = File('${dir.path}/fhirant.sqlite');
    final first = FhirAntDb(NativeDatabase(file));
    await first.saveResource(
      fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'v16',
        'address': [
          {
            'line': ['Zeta Street', 'Alpha Building'],
            'city': 'Middle',
          },
        ],
      }),
    );
    await first.customStatement('DELETE FROM string_search_parameters');
    await first.customStatement('PRAGMA user_version = 16');
    await first.close();

    final second = FhirAntDb(NativeDatabase(file));
    final rows = await second
        .customSelect(
          'SELECT param_index FROM string_search_parameters '
          "WHERE search_name = 'address' ORDER BY param_index",
        )
        .get();
    expect(rows.map((r) => r.read<int>('param_index')).toList(), [0, 100, 200]);
    final version =
        await second.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), second.schemaVersion);
    await second.close();
  });

  test('opening a schema-25 database adds the identifier:of-type rows',
      () async {
    // fhir_db schema 15 indexes one `<param>:of-type` token row per
    // Identifier.type.coding (R4B search.html 3.1.1.4.10, read whole
    // 2026-10-01) and re-extracts the index on upgrade so stored resources
    // get theirs. fhirant overrides `migration`, so the rebuild has to be
    // its own step: a store at 25 holds no such row until it is reopened.
    final file = File('${dir.path}/fhirant.sqlite');
    final first = FhirAntDb(NativeDatabase(file));
    await first.saveResource(
      fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'typed',
        'identifier': [
          {
            'system': 'urn:mrn',
            'value': '446053',
            'type': {
              'coding': [
                {
                  'system': 'http://terminology.hl7.org/CodeSystem/v2-0203',
                  'code': 'MR',
                },
              ],
            },
          },
        ],
      }),
    );
    await first.customStatement(
      "DELETE FROM token_search_parameters WHERE search_name LIKE '%:of-type'",
    );
    await first.customStatement('PRAGMA user_version = 25');
    await first.close();

    final second = FhirAntDb(NativeDatabase(file));
    expect(
      (await second.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'identifier:of-type': <String>[
            'http://terminology.hl7.org/CodeSystem/v2-0203|MR|446053',
          ],
        },
      ))
          .map((r) => r.id!.valueString),
      ['typed'],
    );
    final version =
        await second.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), second.schemaVersion);
    await second.close();
  });

  test(
      'opening a schema-27 database gains the owner-claim columns, '
      'and its accounts keep their own passwords', () async {
    final file = File('${dir.path}/fhirant.sqlite');
    final first = FhirAntDb(NativeDatabase(file));
    await first.createUser(username: 'before', passwordHash: 'h', salt: 's');
    for (final column in [
      'awaiting_owner_until',
      'claim_password_hash',
      'claim_salt',
      'claim_code',
    ]) {
      await first.customStatement('ALTER TABLE users DROP COLUMN $column');
    }
    await first.customStatement(
      'ALTER TABLE authorization_codes DROP COLUMN token_generation',
    );
    await first.customStatement('PRAGMA user_version = 27');
    await first.close();

    final second = FhirAntDb(NativeDatabase(file));
    // The columns themselves, read from SQLite: a User read through
    // readNullable answers null for a column that is not there at all.
    Future<Set<String>> columnsOf(String table) async =>
        (await second.customSelect('PRAGMA table_info($table)').get())
            .map((r) => r.read<String>('name'))
            .toSet();
    expect(
      await columnsOf('users'),
      containsAll(<String>[
        'awaiting_owner_until',
        'claim_password_hash',
        'claim_salt',
        'claim_code',
      ]),
    );
    expect(
      await columnsOf('authorization_codes'),
      contains('token_generation'),
    );
    final before = (await second.getUserByUsername('before'))!;
    expect(before.awaitingOwnerUntil, isNull);
    expect(before.claimSent, isFalse);
    await second.awaitOwner(
      before.id,
      'nobody-knows',
      's0',
      DateTime.now().add(const Duration(hours: 12)),
    );
    expect(await second.holdClaim('before', 'mine', 's1', 'BCDFGHJK'), isTrue);
    expect(
      await second.approveClaim(before.id, 'BCDFGHJK'),
      ClaimApproval.approved,
    );
    final version =
        await second.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), second.schemaVersion);
    await second.close();
  });

  group('an account waiting for its owner', () {
    late FhirAntDb db;
    late int id;

    setUp(() async {
      db = FhirAntDb(NativeDatabase.memory());
      id = await db.createUser(
        username: 'owner',
        passwordHash: 'nobody-knows',
        salt: 's0',
        awaitingOwnerUntil: DateTime.now().add(const Duration(hours: 12)),
      );
    });

    tearDown(() => db.close());

    Future<User> row() async => (await db.getUserById(id))!;

    test(
        'holds the password its owner sends, and the right code makes it '
        'the account password', () async {
      expect(await db.holdClaim('owner', 'mine', 's1', 'BCDFGHJK'), isTrue);
      expect((await row()).claimSent, isTrue);
      expect((await row()).passwordHash, 'nobody-knows');
      expect(await db.approveClaim(id, 'BCDFGHJK'), ClaimApproval.approved);
      final after = await row();
      expect(after.passwordHash, 'mine');
      expect(after.salt, 's1');
      expect(after.awaitingOwnerUntil, isNull);
      expect(after.claimSent, isFalse);
      expect(await db.approveClaim(id, 'BCDFGHJK'), ClaimApproval.notAwaiting);
    });

    test('a wrong code drops the password the owner sent', () async {
      await db.holdClaim('owner', 'mine', 's1', 'BCDFGHJK');
      expect(await db.approveClaim(id, 'BCDFGHJL'), ClaimApproval.wrongCode);
      expect((await row()).claimSent, isFalse);
      expect(await db.approveClaim(id, 'BCDFGHJK'), ClaimApproval.nothingSent);
      expect((await row()).passwordHash, 'nobody-knows');
    });

    test('a later password replaces the earlier one', () async {
      await db.holdClaim('owner', 'first', 's1', 'BBBBBBBB');
      await db.holdClaim('owner', 'second', 's2', 'CCCCCCCC');
      expect(await db.approveClaim(id, 'BBBBBBBB'), ClaimApproval.wrongCode);
      await db.holdClaim('owner', 'third', 's3', 'DDDDDDDD');
      expect(await db.approveClaim(id, 'DDDDDDDD'), ClaimApproval.approved);
      expect((await row()).passwordHash, 'third');
    });

    test('nothing is held once the wait has run out', () async {
      await db.awaitOwner(
        id,
        'nobody-knows',
        's0',
        DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(await db.holdClaim('owner', 'mine', 's1', 'BCDFGHJK'), isFalse);
      expect(await db.approveClaim(id, 'BCDFGHJK'), ClaimApproval.expired);
    });

    test('an account that is not waiting holds nothing', () async {
      final own = await db.createUser(
        username: 'settled',
        passwordHash: 'own',
        salt: 's',
      );
      expect(await db.holdClaim('settled', 'x', 's1', 'BCDFGHJK'), isFalse);
      expect(await db.approveClaim(own, 'BCDFGHJK'), ClaimApproval.notAwaiting);
      expect((await db.getUserById(own))!.passwordHash, 'own');
    });

    test('a new reset drops a password the owner sent before it', () async {
      await db.holdClaim('owner', 'mine', 's1', 'BCDFGHJK');
      await db.awaitOwner(
        id,
        'nobody-knows-2',
        's2',
        DateTime.now().add(const Duration(hours: 12)),
      );
      expect((await row()).claimSent, isFalse);
      expect(await db.approveClaim(id, 'BCDFGHJK'), ClaimApproval.nothingSent);
    });
  });
}
