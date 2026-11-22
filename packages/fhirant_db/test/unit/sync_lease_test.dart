import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:test/test.dart';

/// Schema 33: one `$sync` at a time across every connection to the store.
/// Two connections to one file stand for the phone's Administration screen
/// and the server (or its foreground service), each with its own pipeline.
void main() {
  late Directory dir;
  late File file;
  late FhirAntDb a;
  late FhirAntDb b;
  const fresh = Duration(minutes: 2);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fhirant_db_lease_');
    file = File('${dir.path}/fhirant.sqlite');
    a = FhirAntDb(NativeDatabase(file));
    await a.initialize();
    b = FhirAntDb(NativeDatabase(file));
    await b.initialize();
  });

  tearDown(() async {
    await a.close();
    await b.close();
    await dir.delete(recursive: true);
  });

  test('a second holder is refused while the first holds the lease', () async {
    expect(await a.claimSyncLease('one', 'http://p', staleAfter: fresh), true);
    expect(await b.claimSyncLease('two', 'http://q', staleAfter: fresh), false);
    final lease = (await b.syncLease())!;
    expect(lease.holder, 'one');
    expect(lease.peer, 'http://p');
    // The holder itself cannot take it twice either.
    expect(await a.claimSyncLease('one', 'http://p', staleAfter: fresh), false);
  });

  test('released, it can be taken; renewing a lost lease says so', () async {
    expect(await a.claimSyncLease('one', 'http://p', staleAfter: fresh), true);
    expect(await a.renewSyncLease('one'), true);
    expect(await b.renewSyncLease('two'), false);
    await b.releaseSyncLease('two'); // not its lease: nothing happens
    expect((await a.syncLease())!.holder, 'one');
    await a.releaseSyncLease('one');
    expect(await a.syncLease(), isNull);
    expect(await b.claimSyncLease('two', 'http://q', staleAfter: fresh), true);
    expect(await a.renewSyncLease('one'), false);
  });

  test('a lease not renewed within the limit is taken over', () async {
    expect(await a.claimSyncLease('one', 'http://p', staleAfter: fresh), true);
    // A holder that died 3 minutes ago.
    await a.customStatement(
      'UPDATE sync_lease SET heartbeat = heartbeat - 180',
    );
    expect(await b.claimSyncLease('two', 'http://q', staleAfter: fresh), true);
    expect((await a.syncLease())!.holder, 'two');
    expect(await a.renewSyncLease('one'), false);
  });

  test('the peers synced with, newest first', () async {
    expect(await a.syncPeers(), isEmpty);
    await a.setSyncCursor('http://old', remoteSince: 'r', localSince: 'l');
    await a.customStatement(
      "UPDATE sync_peers SET last_run = last_run - 3600 WHERE peer = 'http://old'",
    );
    await a.setSyncCursor('http://new', remoteSince: 'r', localSince: 'l');
    final peers = await b.syncPeers();
    expect(peers.map((p) => p.peer), ['http://new', 'http://old']);
    final now = DateTime.now();
    expect(now.difference(peers.first.lastRun!).inSeconds.abs(), lessThan(60));
    expect(
      peers.first.lastRun!.difference(peers.last.lastRun!).inSeconds,
      inInclusiveRange(3599, 3601),
    );
  });

  test('a schema-32 store gains the lease when opened', () async {
    await a.customStatement('DROP TABLE sync_lease');
    await a.customStatement('PRAGMA user_version = 32');
    await a.close();
    await b.close();
    a = FhirAntDb(NativeDatabase(file));
    b = FhirAntDb(NativeDatabase(file));
    expect(await a.claimSyncLease('one', 'http://p', staleAfter: fresh), true);
    final version = await a.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 33);
  });
}
