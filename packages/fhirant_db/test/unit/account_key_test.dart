import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:test/test.dart';

/// Each account's own random name, which a token carries as `sub`
/// ([User.accountKey]; schema 31). Ids restart at 1 in every store, so a
/// token naming an id named whoever held that number in another store
/// sharing the signing secret (fhirant REVIEW-2026-10-17, ASVS 5.0.0
/// V10.3.3).
void main() {
  final hex32 = RegExp(r'^[0-9a-f]{32}$');

  test('every new account gets its own key, and is found by it', () async {
    final db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
    addTearDown(db.close);
    final ids = [
      for (var k = 0; k < 50; k++)
        await db.createUser(username: 'user$k', passwordHash: 'h', salt: 's'),
    ];
    final keys = <String>{};
    for (final id in ids) {
      final user = (await db.getUserById(id))!;
      expect(user.accountKey, matches(hex32));
      keys.add(user.accountKey);
      expect((await db.getUserByAccountKey(user.accountKey))!.id, id);
    }
    expect(keys, hasLength(50));
    expect(await db.getUserByAccountKey('0' * 32), isNull);
  });

  test('two stores give their first accounts different keys', () async {
    final a = FhirAntDb(NativeDatabase.memory());
    final b = FhirAntDb(NativeDatabase.memory());
    await a.initialize();
    await b.initialize();
    addTearDown(a.close);
    addTearDown(b.close);
    final ia =
        await a.createUser(username: 'same', passwordHash: 'h', salt: 's');
    final ib =
        await b.createUser(username: 'same', passwordHash: 'h', salt: 's');
    expect(ia, ib);
    expect(
      (await a.getUserById(ia))!.accountKey,
      isNot((await b.getUserById(ib))!.accountKey),
    );
  });

  test('opening a schema-30 store gives its accounts keys', () async {
    final dir = await Directory.systemTemp.createTemp('fhirant_account_key_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/fhirant.sqlite');
    final first = FhirAntDb(NativeDatabase(file));
    await first.initialize();
    for (var k = 0; k < 3; k++) {
      await first.createUser(username: 'old$k', passwordHash: 'h', salt: 's');
    }
    // What a schema-30 store held: no key column, no index.
    await first.customStatement('DROP INDEX idx_users_account_key');
    await first.customStatement('ALTER TABLE users DROP COLUMN account_key');
    await first.customStatement('PRAGMA user_version = 30');
    await first.close();

    final second = FhirAntDb(NativeDatabase(file));
    addTearDown(second.close);
    final users = await second.getAllUsers();
    expect(users, hasLength(3));
    expect(users.map((u) => u.accountKey), everyElement(matches(hex32)));
    expect(users.map((u) => u.accountKey).toSet(), hasLength(3));
    final index = await second
        .customSelect(
          "SELECT name FROM sqlite_master WHERE name = 'idx_users_account_key'",
        )
        .get();
    expect(index, hasLength(1));
    final version =
        await second.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 31);
  });
}
