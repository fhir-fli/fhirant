// Real Argon2id hashes at every sign-in.
@Timeout(Duration(minutes: 4))
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/fhirant_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

import '../integration/test_helpers.dart';

/// A sync from the phone's Administration screen: the operator signs in
/// at the other fhirant server with an account there, never pastes a
/// token (Grey 2026-11-21: "anything requiring the command line is wrong
/// for this app"). Both servers run here, the other over a real socket on
/// the loopback address.
void main() {
  const adminName = 'admin-one';
  const adminPassword = 'Admin-own-pass-7q';
  const peerName = 'peer-admin';
  const peerPassword = 'Peer-own-pass-7q';

  late FhirAntDb db;
  late SyncJobs jobs;
  late DeviceConsole console;
  late DeviceSession admin;
  late ({FhirAntDb db, Handler handler, FhirAntServer server}) peer;
  late HttpServer socket;
  late String peerUrl;
  // When set, the other server holds its answers to anything but sign-in
  // and sign-out until it completes.
  Completer<void>? hold;

  DeviceConsole open() => DeviceConsole(
        db,
        jwtSecret: 'console-test-secret',
        syncJobs: jobs,
        breachedPasswords: null,
      );

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
    await AdminProvisioning.createInitialAdmin(db, adminName, adminPassword);
    jobs = SyncJobs();
    console = open();
    admin = (await console.signIn(adminName, adminPassword)).value!;

    peer = await createTestServer();
    await AdminProvisioning.createInitialAdmin(
      peer.db,
      peerName,
      peerPassword,
    );
    hold = null;
    socket = await shelf_io.serve(
      (request) async {
        if (!request.url.path.startsWith('auth/')) await hold?.future;
        return peer.handler(request);
      },
      InternetAddress.loopbackIPv4,
      0,
    );
    peerUrl = 'http://127.0.0.1:${socket.port}';
  });

  tearDown(() async {
    if (hold != null && !hold!.isCompleted) hold!.complete();
    // The sign-out at the other server follows the sync's end unawaited;
    // its request must land before that server's store closes.
    await jobs.current?.done;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await console.close();
    await socket.close(force: true);
    await peer.server.stop();
    await peer.db.close();
    await db.close();
  });

  Future<SyncStatus> settled(DeviceConsole c, DeviceSession s) async {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    for (;;) {
      final status = await c.syncStatus(s);
      expect(status.ok, isTrue, reason: status.refusal?.text);
      if (status.value!.state != SyncState.running) return status.value!;
      if (DateTime.now().isAfter(deadline)) fail('still running after 60 s');
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }

  Future<void> save(FhirAntDb on, String id, String family) => on.saveResource(
        fhir.Patient.fromJson({
          'resourceType': 'Patient',
          'id': id,
          'name': [
            {'family': family},
          ],
        }),
      );

  test('signed in at the other server, a sync runs and is reported', () async {
    expect((await console.syncPeers(admin)).value, isEmpty);
    expect((await console.syncStatus(admin)).value!.state, SyncState.none);
    await save(db, 'here', 'Here');
    await save(peer.db, 'there', 'There');

    final started = await console.startSync(
      admin,
      '$peerUrl/',
      username: peerName,
      password: peerPassword,
    );
    expect(started.ok, isTrue, reason: started.refusal?.message);
    final done = await settled(console, admin);
    expect(done.state, SyncState.done);
    expect(done.peer, peerUrl);
    expect(done.counts['writtenToPeer'], 1);
    expect(done.counts['writtenHere'], 1);
    expect(done.failures, isEmpty);
    expect(
      await db.getResource(fhir.R4ResourceType.Patient, 'there'),
      isNotNull,
    );
    expect(
      await peer.db.getResource(fhir.R4ResourceType.Patient, 'here'),
      isNotNull,
    );

    final peers = (await console.syncPeers(admin)).value!;
    expect(peers.map((p) => p.peer), [peerUrl]);
    expect(peers.single.lastRun, isNotNull);

    // The sign-in at the other server ended with the sync: its sessions
    // are revoked there.
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (true) {
      final revoked = await peer.db
          .customSelect('SELECT count(*) AS n FROM revoked_tokens')
          .getSingle();
      if (revoked.read<int>('n') >= 1) break;
      if (DateTime.now().isAfter(deadline)) fail('peer session not ended');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  });

  test("a wrong password at the other server is that server's refusal",
      () async {
    final started = await console.startSync(
      admin,
      peerUrl,
      username: peerName,
      password: 'not-the-password',
    );
    expect(started.ok, isFalse);
    expect(started.refusal!.fromPeer, isTrue);
    expect(started.refusal!.status, 401);
    expect(started.refusal!.message, startsWith('The other server: '));
    expect((await console.syncStatus(admin)).value!.state, SyncState.none);
  });

  test('an address the route would refuse is refused before any sign-in',
      () async {
    for (final bad in ['ftp://x', 'not a url', 'http://u:p@127.0.0.1:1']) {
      final r = await console.startSync(
        admin,
        bad,
        username: peerName,
        password: peerPassword,
      );
      expect(r.ok, isFalse, reason: bad);
      expect(r.refusal!.status, 400, reason: bad);
      expect(r.refusal!.fromPeer, isFalse, reason: bad);
    }
  });

  test('a server nobody answers at is named in the refusal', () async {
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();
    final r = await console.startSync(
      admin,
      'http://127.0.0.1:$port',
      username: peerName,
      password: peerPassword,
    );
    expect(r.refusal!.fromPeer, isTrue);
    expect(r.refusal!.message, contains('Could not reach'));
  });

  test('the sync outlives the session that started it', () async {
    for (var k = 0; k < 600; k++) {
      await save(db, 'p$k', 'Family$k');
    }
    hold = Completer<void>();
    final started = await console.startSync(
      admin,
      peerUrl,
      username: peerName,
      password: peerPassword,
    );
    expect(started.ok, isTrue, reason: started.refusal?.message);
    // The screen signs out and its console closes.
    await console.signOut(admin);
    await console.close();

    console = open();
    admin = (await console.signIn(adminName, adminPassword)).value!;
    expect((await console.syncStatus(admin)).value!.state, SyncState.running);
    hold!.complete();
    final done = await settled(console, admin);
    expect(done.state, SyncState.done);
    expect(done.counts['writtenToPeer'], 600);
    expect(done.failures, isEmpty);
  });

  test('a second sync while one runs is refused, naming the first', () async {
    hold = Completer<void>();
    expect(
      (await console.startSync(
        admin,
        peerUrl,
        username: peerName,
        password: peerPassword,
      ))
          .ok,
      isTrue,
    );
    final second = await console.startSync(
      admin,
      peerUrl,
      username: peerName,
      password: peerPassword,
    );
    expect(second.ok, isFalse);
    expect(second.refusal!.status, 409);
    expect(second.refusal!.message, contains('A sync with $peerUrl'));
    hold!.complete();
    expect((await settled(console, admin)).state, SyncState.done);
  });
}
