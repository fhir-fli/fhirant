import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:test/test.dart';

/// Schema 29: what `$sync` remembers about each peer server.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fhirant_db_sync_');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('a schema-28 store gains the sync tables when it is opened', () async {
    final file = File('${dir.path}/fhirant.sqlite');
    final first = FhirAntDb(NativeDatabase(file));
    await first.createUser(username: 'before', passwordHash: 'h', salt: 's');
    await first.customStatement('DROP TABLE sync_peers');
    await first.customStatement('DROP TABLE sync_pairs');
    await first.customStatement('PRAGMA user_version = 28');
    await first.close();

    final second = FhirAntDb(NativeDatabase(file));
    final tables = (await second
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table'",
            )
            .get())
        .map((r) => r.read<String>('name'))
        .toSet();
    expect(tables, containsAll(<String>['sync_peers', 'sync_pairs']));
    await second.setSyncPair(
      'http://peer',
      'Patient/a',
      local: '1',
      remote: '3',
    );
    expect(
      await second.syncPair('http://peer', 'Patient/a'),
      (
        local: '1',
        remote: '3',
      ),
    );
    final version =
        await second.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), second.schemaVersion);
    await second.close();
  });

  group('sync bookkeeping', () {
    late FhirAntDb db;

    setUp(() async {
      db = FhirAntDb(NativeDatabase.memory());
      await db.initialize();
    });

    tearDown(() => db.close());

    test('a peer never synced has no cursor and no pairs', () async {
      expect(await db.syncCursor('http://peer'), isNull);
      expect(await db.syncPair('http://peer', 'Patient/a'), isNull);
    });

    test('the cursor and pairs are kept per peer and replaced on write',
        () async {
      await db.setSyncCursor(
        'http://a',
        remoteSince: '2026-11-19T10:00:00.000Z',
        localSince: '2026-11-19T10:00:01.000Z',
      );
      await db.setSyncCursor(
        'http://a',
        remoteSince: '2026-11-19T11:00:00.000Z',
        localSince: null,
      );
      expect(
        await db.syncCursor('http://a'),
        (
          remoteSince: '2026-11-19T11:00:00.000Z',
          localSince: null,
        ),
      );
      expect(await db.syncCursor('http://b'), isNull);

      await db.setSyncPair('http://a', 'Patient/x', local: '1', remote: '1');
      await db.setSyncPair('http://a', 'Patient/x', local: '2', remote: '5');
      await db.setSyncPair('http://b', 'Patient/x', local: '9', remote: null);
      expect(
        await db.syncPair('http://a', 'Patient/x'),
        (
          local: '2',
          remote: '5',
        ),
      );
      expect(
        await db.syncPair('http://b', 'Patient/x'),
        (
          local: '9',
          remote: null,
        ),
      );
    });

    test('the sync tables are server state, not part of the FHIR record', () {
      expect(
        FhirAntDb.serverStateTables,
        containsAll(<String>['sync_peers', 'sync_pairs']),
      );
    });
  });
}
