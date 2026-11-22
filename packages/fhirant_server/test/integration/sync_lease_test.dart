import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:fhirant_server/src/sync/sync_job.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

import 'test_helpers.dart';

/// One `$sync` at a time on the device. The phone's Administration screen
/// runs the server's pipeline itself (`DeviceConsole`), apart from the
/// server or its foreground service, so each has its own [SyncJobs]; the
/// store's lease is what they share. Two servers on one store stand for
/// the two here.
void main() {
  late FhirAntDb db;
  late ({FhirAntDb db, Handler handler, FhirAntServer server}) peer;
  late HttpServer socket;
  late String peerUrl;
  // Holds the peer's answers until completed.
  late Completer<void> gate;

  FhirAntServer serverOn(SyncJobs jobs) => FhirAntServer(
        db,
        jwtSecret: testJwtSecret,
        devMode: true,
        syncJobs: jobs,
        breachedPasswords: null,
      );

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
    peer = await createTestServer(devMode: true);
    gate = Completer<void>();
    socket = await shelf_io.serve(
      (request) async {
        await gate.future;
        return peer.handler(request);
      },
      InternetAddress.loopbackIPv4,
      0,
    );
    peerUrl = 'http://127.0.0.1:${socket.port}';
  });

  tearDown(() async {
    if (!gate.isCompleted) gate.complete();
    await socket.close(force: true);
    await peer.server.stop();
    await peer.db.close();
    await db.close();
  });

  Request kick(String url) => testRequest(
        'POST',
        r'/$sync',
        headers: {'content-type': 'application/fhir+json'},
        body: jsonEncode({
          'resourceType': 'Parameters',
          'parameter': [
            {'name': 'peer', 'valueUrl': url},
          ],
        }),
      );

  Future<Response> finished(Handler handler) async {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    for (;;) {
      final status = await handler(testRequest('GET', r'/$sync-status'));
      if (status.statusCode != 202) return status;
      if (DateTime.now().isAfter(deadline)) fail('still running after 60 s');
      // Under the server's 600 requests a minute.
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }

  test('a second pipeline on the store is refused while one syncs, and sees it',
      () async {
    final a = serverOn(SyncJobs());
    final b = serverOn(SyncJobs());
    final ha = a.createHandler(a.createRouter());
    final hb = b.createHandler(b.createRouter());

    expect((await ha(kick(peerUrl))).statusCode, 202);
    final refused = await hb(kick('http://127.0.0.1:1'));
    expect(refused.statusCode, 409);
    expect(await refused.readAsString(), contains('A sync with $peerUrl'));
    final seen = await hb(testRequest('GET', r'/$sync-status'));
    expect(seen.statusCode, 202);
    expect(seen.headers['x-progress'], contains(peerUrl));
    expect(seen.headers['x-progress'], contains('elsewhere on this device'));

    gate.complete();
    expect((await finished(ha)).statusCode, 200);
    expect(await db.syncLease(), isNull);
    // Released: the other pipeline may sync now.
    expect((await hb(kick(peerUrl))).statusCode, 202);
    expect((await finished(hb)).statusCode, 200);
    await a.stop();
    await b.stop();
  });

  test('a sync whose lease was taken over stops before its next write',
      () async {
    final jobs = SyncJobs(heartbeat: const Duration(milliseconds: 20));
    final a = serverOn(jobs);
    final ha = a.createHandler(a.createRouter());
    await db.saveResource(
      fhir.Patient.fromJson({'resourceType': 'Patient', 'id': 'only-here'}),
    );

    expect((await ha(kick(peerUrl))).statusCode, 202);
    // Another sync takes the lease while this one waits on the peer.
    await db.customStatement(
      "UPDATE sync_lease SET holder = 'someone-else'",
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    gate.complete();
    final job = jobs.current!;
    await job.done.timeout(const Duration(seconds: 60));
    expect(job.error, contains('Another sync took over'));
    expect(
      await peer.db.getResource(fhir.R4ResourceType.Patient, 'only-here'),
      isNull,
    );
    // Not its lease to release: the other holder keeps it, and the status
    // reports that holder's sync as running.
    expect((await db.syncLease())!.holder, 'someone-else');
    final elsewhere = await ha(testRequest('GET', r'/$sync-status'));
    expect(elsewhere.statusCode, 202);
    expect(elsewhere.headers['x-progress'], contains('elsewhere'));
    await db.releaseSyncLease('someone-else');
    final status = await finished(ha);
    expect(status.statusCode, 500);
    expect(await status.readAsString(), contains('Another sync took over'));
    await a.stop();
  });
}
