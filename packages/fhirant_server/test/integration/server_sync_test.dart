import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:fhirant_server/src/services/disk_space.dart';
import 'package:fhirant_server/src/sync/merge.dart';
import 'package:fhirant_server/src/sync/sync_endpoint.dart';
import 'package:fhirant_server/src/sync/sync_job.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

import 'test_helpers.dart';

/// `$sync` between two running servers, each with its own store, the peer
/// over a real socket (Grey, 2026-10-30 and 2026-11-19: new resources are
/// copied, a field changed on one side takes that change, a field both
/// changed takes the newer save by each server's own clock, every version
/// stays in history).
void main() {
  late ({FhirAntDb db, Handler handler, FhirAntServer server}) here;
  late ({FhirAntDb db, Handler handler, FhirAntServer server}) there;
  late HttpServer peerSocket;
  late String peerUrl;
  // Every request the peer received, as "METHOD path".
  late List<String> peerRequests;

  setUp(() async {
    here = await createTestServer(devMode: true);
    there = await createTestServer(devMode: true);
    peerRequests = [];
    peerSocket = await shelf_io.serve(
      (request) async {
        if (request.method != 'POST') {
          peerRequests.add('${request.method} ${request.url.path}');
          return there.handler(request);
        }
        // A POST is named by its Bundle type too.
        final body = await request.readAsString();
        final type = body.isEmpty ? null : (jsonDecode(body) as Map)['type'];
        peerRequests.add('POST ${request.url.path}${type ?? ''}');
        return there.handler(request.change(body: body));
      },
      InternetAddress.loopbackIPv4,
      0,
    );
    peerUrl = 'http://127.0.0.1:${peerSocket.port}';
  });

  tearDown(() async {
    await peerSocket.close(force: true);
    await here.server.stop();
    await there.server.stop();
    await here.db.close();
    await there.db.close();
  });

  /// Runs `$sync` on [here] (or [on], as [caller]) against the peer and
  /// returns the finished status as name → values.
  Future<Map<String, List<Object?>>> sync({
    String? token,
    Handler? on,
    String? caller,
  }) async {
    final handler = on ?? here.handler;
    final kick = await handler(
      testRequest(
        'POST',
        r'/$sync',
        authToken: caller,
        headers: {'content-type': 'application/fhir+json'},
        body: jsonEncode({
          'resourceType': 'Parameters',
          'parameter': [
            {'name': 'peer', 'valueUrl': peerUrl},
            if (token != null) {'name': 'token', 'valueString': token},
          ],
        }),
      ),
    );
    expect(kick.statusCode, 202, reason: await kick.readAsString());
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    for (;;) {
      final status = await handler(
        testRequest('GET', r'/$sync-status', authToken: caller),
      );
      if (status.statusCode != 202) {
        final body = await status.readAsString();
        expect(status.statusCode, 200, reason: body);
        final out = <String, List<Object?>>{};
        for (final p in (jsonDecode(body)['parameter'] as List)
            .cast<Map<String, dynamic>>()) {
          final value =
              p.entries.firstWhere((e) => e.key.startsWith('value')).value;
          out.putIfAbsent(p['name'] as String, () => []).add(value);
        }
        return out;
      }
      if (DateTime.now().isAfter(deadline)) {
        fail(r'$sync still running after 60 s');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  int count(Map<String, List<Object?>> r, String name) =>
      (r[name]?.single as int?) ?? 0;

  Future<Map<String, dynamic>?> read(FhirAntDb db, String id) async =>
      (await db.getResource(fhir.R4ResourceType.Patient, id))?.toJson();

  Future<void> save(FhirAntDb db, Map<String, dynamic> fields) async {
    // Each save one millisecond apart at least, so saves on the two sides
    // have distinct times in the order the test makes them.
    await Future<void>.delayed(const Duration(milliseconds: 3));
    await db.saveResource(
      fhir.Patient.fromJson({'resourceType': 'Patient', ...fields}),
    );
  }

  Future<void> remove(FhirAntDb db, String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 3));
    await db.deleteResource(fhir.R4ResourceType.Patient, id);
  }

  const start = {
    'id': 'p1',
    'gender': 'female',
    'birthDate': '1980-01-01',
  };

  test('a resource new on either side is copied to the other, its id kept',
      () async {
    await save(here.db, {'id': 'only-here', 'gender': 'male'});
    await save(there.db, {'id': 'only-there', 'gender': 'female'});

    final r = await sync();

    // Each side gets the other's resource, as it is. R4B resource.html,
    // Meta.source (read 2026-11-20): "On receiving a write operation, the
    // server SHOULD generally leave this unchanged". The sync adds none, so
    // the copy is the original's content and the original is not written
    // again (measured 2026-11-20: adding one wrote all 10,000 resources
    // back to the server they came from).
    expect(count(r, 'writtenToPeer'), 1);
    expect(count(r, 'writtenHere'), 1);
    expect(r['failure'], isNull);
    expect((await read(there.db, 'only-here'))!['gender'], 'male');
    expect((await read(here.db, 'only-there'))!['gender'], 'female');
    expect((await read(here.db, 'only-there'))!['meta']['source'], isNull);
    expect((await read(there.db, 'only-here'))!['meta']['source'], isNull);
    expect(
      await here.db
          .getResourceHistory(fhir.R4ResourceType.Patient, 'only-here'),
      hasLength(1),
    );
    expect(
      await there.db
          .getResourceHistory(fhir.R4ResourceType.Patient, 'only-there'),
      hasLength(1),
    );
  });

  test(
      'a first sync copies in one batch each way, and the next reads no '
      "resource's history", () async {
    for (final id in ['h1', 'h2', 'h3']) {
      await save(here.db, {'id': id});
    }
    for (final id in ['t1', 't2']) {
      await save(there.db, {'id': id});
    }

    final first = await sync();

    expect(count(first, 'writtenToPeer'), 3);
    expect(count(first, 'writtenHere'), 2);
    // One transaction to the peer, no write of its own per resource, and no
    // resource's history read: the copies came from the history pages.
    expect(peerRequests.where((r) => r == 'POST transaction'), hasLength(1));
    expect(peerRequests.where((r) => r.startsWith('PUT ')), isEmpty);
    final perResource = RegExp('^GET [A-Za-z]+/[^/]+/_history');
    expect(peerRequests.where(perResource.hasMatch), isEmpty);
    for (final id in ['t1', 't2']) {
      expect(
        await here.db.getResourceHistory(fhir.R4ResourceType.Patient, id),
        hasLength(1),
      );
    }

    peerRequests.clear();
    final second = await sync();

    // The first sync's own writes are all the two sides show; each is the
    // version it recorded, so none is read or written again.
    expect(count(second, 'considered'), 5);
    expect(count(second, 'unchanged'), 5);
    expect(count(second, 'writtenToPeer'), 0);
    expect(count(second, 'writtenHere'), 0);
    expect(peerRequests.where(perResource.hasMatch), isEmpty);
    expect(peerRequests.where((r) => !r.startsWith('GET ')), isEmpty);
  });

  test(
      'this side read whole after its clock went back copies nothing the '
      'peer already has', () async {
    for (final id in ['a', 'b', 'c']) {
      await save(here.db, {'id': id});
    }
    await sync();
    // The second run moves the peer's cursor past the first run's copies;
    // `_since` keeps the newest of them, the others are not shown again.
    await sync();
    // This side's cursor ahead of its clock: it is read whole next time,
    // and the peer, read since its cursor, shows at most one of them.
    await here.db.customStatement(
      "UPDATE sync_peers SET local_since = '2099-01-01T00:00:00.000Z'",
    );
    peerRequests.clear();

    final r = await sync();

    expect(count(r, 'writtenToPeer'), 0);
    expect(count(r, 'unchanged'), 3);
    expect(peerRequests.where((r) => r.startsWith('POST')), isEmpty);
  });

  test('copies past 500 go in more than one batch', () async {
    await here.db.saveResources([
      for (var i = 0; i < 501; i++) fhir.Patient(id: 'p$i'.toFhirString),
    ]);

    final r = await sync();

    expect(count(r, 'writtenToPeer'), 501);
    expect(r['failure'], isNull);
    expect(peerRequests.where((r) => r == 'POST transaction'), hasLength(2));
    expect(
      await there.db.getResourceCount(fhir.R4ResourceType.Patient),
      501,
    );
  });

  test("copies this server's floor would not hold are refused, not lost",
      () async {
    final disk = _FillsUp();
    final full = await createTestServer(devMode: true, diskSpace: disk);
    addTearDown(() async {
      await full.server.stop();
      await full.db.close();
    });
    for (final id in ['t1', 't2']) {
      await save(there.db, {'id': id});
    }

    final r = await sync(on: full.handler);

    expect(count(r, 'writtenHere'), 0);
    expect(r['failure'], hasLength(2));
    expect('${r['failure']}', contains('507'));
    expect(await full.db.syncCursor(peerUrl), isNull);
  });

  test('a resource this store lost after the last sync is brought back',
      () async {
    await save(here.db, {'id': 'kept', 'gender': 'male'});
    await sync();
    // As a store restored from before the sync: the resource and the
    // cursor gone, the pair left.
    for (final table in ['resources', 'resources_history']) {
      await here.db.customStatement(
        "DELETE FROM $table WHERE resource_type = 'Patient' AND id = 'kept'",
      );
    }
    await here.db.customStatement('DELETE FROM sync_peers');

    final r = await sync();

    expect(r['failure'], isNull);
    expect((await read(here.db, 'kept'))?['gender'], 'male');
  });

  test('a meta.source the original carries reaches the copy unchanged',
      () async {
    await save(there.db, {
      'id': 'sourced',
      'meta': {'source': 'http://lab.example/fhir'},
    });

    await sync();

    expect(
      (await read(here.db, 'sourced'))!['meta']['source'],
      'http://lab.example/fhir',
    );
  });

  test('a second sync with nothing changed writes nothing', () async {
    await save(here.db, {'id': 'a', 'gender': 'male'});
    await save(there.db, {'id': 'b', 'gender': 'female'});
    await sync();
    final hereVersions =
        await here.db.getResourceHistory(fhir.R4ResourceType.Patient, 'a');
    final thereVersions =
        await there.db.getResourceHistory(fhir.R4ResourceType.Patient, 'a');

    final r = await sync();

    expect(count(r, 'writtenToPeer'), 0);
    expect(count(r, 'writtenHere'), 0);
    expect(
      await here.db.getResourceHistory(fhir.R4ResourceType.Patient, 'a'),
      hasLength(hereVersions.length),
    );
    expect(
      await there.db.getResourceHistory(fhir.R4ResourceType.Patient, 'a'),
      hasLength(thereVersions.length),
    );
  });

  test('fields changed on different sides are both kept', () async {
    await save(here.db, start);
    await sync();
    await save(here.db, {...start, 'gender': 'male'});
    await save(there.db, {...start, 'birthDate': '1981-02-02'});

    final r = await sync();

    expect(r['conflict'], isNull);
    for (final db in [here.db, there.db]) {
      final p = (await read(db, 'p1'))!;
      expect(p['gender'], 'male');
      expect(p['birthDate'], '1981-02-02');
    }
  });

  test('a field both sides changed takes the later save: here later', () async {
    await save(here.db, start);
    await sync();
    await save(there.db, {...start, 'birthDate': '1982-01-01'});
    await save(here.db, {...start, 'birthDate': '1981-01-01'});

    final r = await sync();

    expect(r['conflict'], hasLength(1));
    expect(r['conflict']!.single, contains('birthDate: local kept'));
    for (final db in [here.db, there.db]) {
      expect((await read(db, 'p1'))!['birthDate'], '1981-01-01');
    }
  });

  test('a field both sides changed takes the later save: peer later', () async {
    await save(here.db, start);
    await sync();
    await save(here.db, {...start, 'birthDate': '1981-01-01'});
    await save(there.db, {...start, 'birthDate': '1982-01-01'});

    final r = await sync();

    expect(r['conflict']!.single, contains('birthDate: remote kept'));
    for (final db in [here.db, there.db]) {
      expect((await read(db, 'p1'))!['birthDate'], '1982-01-01');
    }
  });

  test("every version stays in each side's history", () async {
    await save(here.db, start);
    await sync();
    await save(here.db, {...start, 'gender': 'male'});
    await sync();

    final versions =
        await there.db.getResourceHistory(fhir.R4ResourceType.Patient, 'p1');
    expect(
      // Newest first.
      versions.reversed.map((v) => v.toJson()['gender']),
      containsAllInOrder(<String>['female', 'male']),
    );
  });

  test("a delete newer than the other side's edit deletes it on both",
      () async {
    await save(here.db, start);
    await sync();
    await save(here.db, {...start, 'gender': 'male'});
    await remove(there.db, 'p1');

    final r = await sync();

    expect(count(r, 'deletedHere'), 1);
    expect(await read(here.db, 'p1'), isNull);
    expect(await read(there.db, 'p1'), isNull);
  });

  test("an edit newer than the other side's delete keeps it on both", () async {
    await save(here.db, start);
    await sync();
    await remove(there.db, 'p1');
    await save(here.db, {...start, 'gender': 'male'});

    await sync();

    expect((await read(here.db, 'p1'))!['gender'], 'male');
    expect((await read(there.db, 'p1'))!['gender'], 'male');
  });

  test('audit events and subscriptions are not synced', () async {
    await save(here.db, start);
    final r = await sync();
    // The kickoff and the status polls were audited here; none of those
    // AuditEvents reached the peer.
    await here.server.auditQueue.drain();
    expect(
      await here.db.getResourceCount(fhir.R4ResourceType.AuditEvent),
      greaterThan(0),
    );
    expect(
      await there.db.getResourceCount(fhir.R4ResourceType.AuditEvent),
      0,
    );
    expect(r['failure'], isNull);
    expect(
      syncSkippedTypes,
      containsAll(<String>['AuditEvent', 'Subscription']),
    );
  });

  group('runs that do not finish', () {
    /// The peer, failing every write after [allowed] writes went through,
    /// including the entries of a batch past that count.
    SyncClient failingPeer(int allowed) =>
        SyncClient(_GoesDown(RemoteEndpoint(Uri.parse(peerUrl)), allowed));

    SyncClient localClient() => SyncClient(
          LocalEndpoint(
            here.server.routerHandler,
            Uri.parse('http://localhost:8080'),
            null,
          ),
        );

    test('a run cut off partway moves no cursor, and the next run finishes',
        () async {
      for (final id in ['a', 'b', 'c']) {
        await save(here.db, {'id': id, 'gender': 'male'});
      }
      final report = SyncReport();
      await Synchronizer(
        db: here.db,
        peer: peerUrl,
        local: localClient(),
        remote: failingPeer(1),
        report: report,
      ).run();
      expect(report.writtenToPeer, 1);
      expect(report.failures, hasLength(2));
      expect(await here.db.syncCursor(peerUrl), isNull);

      final r = await sync();
      expect(r['failure'], isNull);
      for (final id in ['a', 'b', 'c']) {
        expect((await read(there.db, id))!['gender'], 'male');
      }
      expect(await here.db.syncCursor(peerUrl), isNotNull);
    });

    test('a peer that refuses the transaction takes the copies as a batch',
        () async {
      for (final id in ['a', 'b', 'c']) {
        await save(here.db, {'id': id});
      }
      final report = SyncReport();
      await Synchronizer(
        db: here.db,
        peer: peerUrl,
        local: localClient(),
        remote: failingPeer(1000),
        report: report,
      ).run();
      expect(report.failures, isEmpty);
      expect(report.writtenToPeer, 3);
      for (final id in ['a', 'b', 'c']) {
        expect(await read(there.db, id), isNotNull);
      }
    });

    test('copies the peer refuses whole are each a failure', () async {
      for (final id in ['a', 'b']) {
        await save(here.db, {'id': id});
      }
      final report = SyncReport();
      await Synchronizer(
        db: here.db,
        peer: peerUrl,
        local: localClient(),
        remote: SyncClient(
          _Intercept(
            RemoteEndpoint(Uri.parse(peerUrl)),
            (method, path) => method == 'POST'
                ? (status: 500, headers: <String, String>{}, body: 'no')
                : null,
          ),
        ),
        report: report,
      ).run();
      expect(report.writtenToPeer, 0);
      expect(report.failures, hasLength(2));
      expect(report.failures.first, contains('answered 500'));
      expect(await here.db.syncCursor(peerUrl), isNull);
    });

    test('a resource the peer changes during the sync is merged next time',
        () async {
      await save(here.db, start);
      await sync();
      await save(here.db, {...start, 'gender': 'male'});
      // Just before the sync's write reaches the peer, someone there
      // changes another field.
      var raced = false;
      final racingPeer = SyncClient(
        _Intercept(
          RemoteEndpoint(Uri.parse(peerUrl)),
          (method, path) {
            if (method == 'PUT' && !raced) {
              raced = true;
              return null;
            }
            return null;
          },
          before: (method, path) async {
            if (method == 'PUT' && !raced) {
              await save(there.db, {...start, 'birthDate': '1990-09-09'});
            }
          },
        ),
      );
      final report = SyncReport();
      await Synchronizer(
        db: here.db,
        peer: peerUrl,
        local: localClient(),
        remote: racingPeer,
        report: report,
      ).run();
      expect(report.retryLater, hasLength(1));
      expect((await read(there.db, 'p1'))!['gender'], 'female');

      await sync();
      for (final db in [here.db, there.db]) {
        final p = (await read(db, 'p1'))!;
        expect(p['gender'], 'male');
        expect(p['birthDate'], '1990-09-09');
      }
    });
  });

  test("a sync started from the peer's side agrees with this side", () async {
    final hereSocket =
        await shelf_io.serve(here.handler, InternetAddress.loopbackIPv4, 0);
    final hereUrl = 'http://127.0.0.1:${hereSocket.port}';
    await save(here.db, start);
    await sync();
    await save(there.db, {...start, 'gender': 'male'});
    await save(here.db, {...start, 'birthDate': '1981-01-01'});
    await save(there.db, {...start, 'gender': 'male', 'birthDate': '1982'});

    // The peer runs it, against this server: it has no record of the
    // earlier sync, so each side's whole history is read.
    final kick = await there.handler(
      testRequest(
        'POST',
        r'/$sync',
        headers: {'content-type': 'application/fhir+json'},
        body: jsonEncode({
          'resourceType': 'Parameters',
          'parameter': [
            {'name': 'peer', 'valueUrl': hereUrl},
          ],
        }),
      ),
    );
    expect(kick.statusCode, 202);
    Response status;
    do {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      status = await there.handler(testRequest('GET', r'/$sync-status'));
    } while (status.statusCode == 202);
    expect(status.statusCode, 200, reason: await status.readAsString());
    for (final db in [here.db, there.db]) {
      final p = (await read(db, 'p1'))!;
      expect(p['gender'], 'male');
      expect(p['birthDate'], '1982');
    }

    // And this side's next sync finds nothing to change.
    final r = await sync();
    expect(count(r, 'writtenToPeer'), 0);
    expect(count(r, 'writtenHere'), 0);
    await hereSocket.close(force: true);
  });

  test('only an administrator or a system scope may start a sync', () async {
    final secured = await createTestServer();
    final clinician = await issueTestToken(secured.db, username: 'nurse');
    final refused = await secured.handler(
      testRequest(
        'POST',
        r'/$sync',
        authToken: clinician,
        headers: {'content-type': 'application/fhir+json'},
        body: jsonEncode({
          'resourceType': 'Parameters',
          'parameter': [
            {'name': 'peer', 'valueUrl': peerUrl},
          ],
        }),
      ),
    );
    expect(refused.statusCode, 403);
    await secured.server.stop();
    await secured.db.close();
  });

  test('a peer that is not an http(s) URL is refused', () async {
    for (final peer in ['file:///etc/passwd', 'not a url', '']) {
      final r = await here.handler(
        testRequest(
          'POST',
          r'/$sync',
          headers: {'content-type': 'application/fhir+json'},
          body: jsonEncode({
            'resourceType': 'Parameters',
            'parameter': [
              {'name': 'peer', 'valueUrl': peer},
            ],
          }),
        ),
      );
      expect(r.statusCode, 400, reason: peer);
    }
  });

  test('a peer that needs a token gets the one given', () async {
    final secured = await createTestServer();
    final socket =
        await shelf_io.serve(secured.handler, InternetAddress.loopbackIPv4, 0);
    final admin =
        await issueTestToken(secured.db, username: 'peer-admin', role: 'admin');
    peerUrl = 'http://127.0.0.1:${socket.port}';
    await save(here.db, {'id': 'carried', 'gender': 'male'});

    final withToken = await sync(token: admin);
    expect(withToken['failure'], isNull);
    expect(
      (await secured.db.getResource(fhir.R4ResourceType.Patient, 'carried'))
          ?.toJson()['gender'],
      'male',
    );
    await socket.close(force: true);
    await secured.server.stop();
    await secured.db.close();
  });

  test('without the token the peer refuses and the sync says so', () async {
    final secured = await createTestServer();
    final socket =
        await shelf_io.serve(secured.handler, InternetAddress.loopbackIPv4, 0);
    peerUrl = 'http://127.0.0.1:${socket.port}';
    await save(here.db, {'id': 'carried', 'gender': 'male'});

    final kick = await here.handler(
      testRequest(
        'POST',
        r'/$sync',
        headers: {'content-type': 'application/fhir+json'},
        body: jsonEncode({
          'resourceType': 'Parameters',
          'parameter': [
            {'name': 'peer', 'valueUrl': peerUrl},
          ],
        }),
      ),
    );
    expect(kick.statusCode, 202);
    Response status;
    do {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      status = await here.handler(testRequest('GET', r'/$sync-status'));
    } while (status.statusCode == 202);
    expect(status.statusCode, 500);
    expect(await status.readAsString(), contains('401'));
    await socket.close(force: true);
    await secured.server.stop();
    await secured.db.close();
  });

  group('what the sync does not trust', () {
    test('a peer naming something that is not a resource stops the sync',
        () async {
      // A history entry whose type and id would make the key a path to
      // another route here: `admin/users/2/role` is the account role
      // route.
      for (final resource in [
        {'resourceType': 'admin', 'id': 'users/2/role', 'role': 'admin'},
        {'resourceType': 'Patient', 'id': r'a$b'},
      ]) {
        final hostile = SyncClient(
          _Intercept(RemoteEndpoint(Uri.parse(peerUrl)), (method, path) {
            if (method != 'GET' || !path.startsWith('_history')) return null;
            return (
              status: 200,
              headers: <String, String>{},
              body: jsonEncode({
                'resourceType': 'Bundle',
                'type': 'history',
                'entry': [
                  {
                    'resource': resource,
                    'request': {'method': 'PUT', 'url': 'x'},
                    'response': {
                      'status': '200',
                      'etag': 'W/"1"',
                      'lastModified': '2026-11-19T10:00:00Z',
                    },
                  },
                ],
              }),
            );
          }),
        );
        final sentHere = <String>[];
        final local = SyncClient(
          _Intercept(
            LocalEndpoint(
              here.server.routerHandler,
              Uri.parse('http://localhost:8080'),
              null,
            ),
            (method, path) {
              sentHere.add('$method $path');
              return null;
            },
          ),
        );
        await expectLater(
          Synchronizer(
            db: here.db,
            peer: peerUrl,
            local: local,
            remote: hostile,
            report: SyncReport(),
          ).run(),
          throwsA(isA<SyncFailure>()),
          reason: '$resource',
        );
        expect(
          sentHere.where((r) => !r.startsWith('GET _history')),
          isEmpty,
          reason: '$resource',
        );
      }
    });

    test('a caller who may only read writes nothing here', () async {
      final secured = await createTestServer();
      final reader = await issueTestToken(
        secured.db,
        username: 'reader',
        scopes: ['system/*.rs'],
      );
      await save(there.db, {'id': 'from-peer', 'gender': 'male'});

      final r = await sync(on: secured.handler, caller: reader);

      expect(r['failure'], isNotNull);
      expect(r['failure']!.single, contains('403'));
      expect(
        await secured.db.getResource(fhir.R4ResourceType.Patient, 'from-peer'),
        isNull,
      );
      await secured.server.stop();
      await secured.db.close();
    });

    test("what the sync writes here is audited as its caller's", () async {
      final secured = await createTestServer();
      final admin = await issueTestToken(
        secured.db,
        username: 'sync-admin',
        role: 'admin',
      );
      await save(there.db, {'id': 'audited', 'gender': 'male'});

      final r = await sync(on: secured.handler, caller: admin);
      expect(r['failure'], isNull);
      await secured.server.auditQueue.drain();

      final events = [
        for (final e in await secured.db
            .getResourcesByType(fhir.R4ResourceType.AuditEvent))
          jsonEncode(e.toJson()),
      ];
      final writes = events.where(
        (e) =>
            e.contains('Patient/audited') &&
            e.contains('"action":"U"') &&
            e.contains('sync-admin'),
      );
      expect(writes, isNotEmpty, reason: events.join('\n'));
      await secured.server.stop();
      await secured.db.close();
    });

    test('a peer URL carrying a user name or password is refused', () async {
      final r = await here.handler(
        testRequest(
          'POST',
          r'/$sync',
          headers: {'content-type': 'application/fhir+json'},
          body: jsonEncode({
            'resourceType': 'Parameters',
            'parameter': [
              {
                'name': 'peer',
                'valueUrl': 'http://admin:secret@127.0.0.1:${peerSocket.port}',
              },
            ],
          }),
        ),
      );
      expect(r.statusCode, 400);
    });
  });

  group('a clock set back', () {
    test("a peer's history is read in its order, not by its times", () async {
      // v3 saved after the clock went back, so stamped before v2.
      final peer = SyncClient(
        _Intercept(RemoteEndpoint(Uri.parse(peerUrl)), (method, path) {
          if (!path.startsWith('Patient/p1/_history')) return null;
          Map<String, dynamic> entry(String v, String at, String gender) => {
                'resource': {
                  'resourceType': 'Patient',
                  'id': 'p1',
                  'gender': gender,
                },
                'request': {'method': 'PUT', 'url': 'Patient/p1'},
                'response': {
                  'status': '200',
                  'etag': 'W/"$v"',
                  'lastModified': at,
                },
              };
          return (
            status: 200,
            headers: <String, String>{},
            body: jsonEncode({
              'resourceType': 'Bundle',
              'type': 'history',
              'entry': [
                entry('3', '2026-11-19T09:00:00Z', 'other'),
                entry('2', '2026-11-19T10:00:00Z', 'male'),
                entry('1', '2026-11-19T08:00:00Z', 'female'),
              ],
            }),
          );
        }),
      );
      final versions = await peer.history('Patient/p1');
      expect(versions.map((v) => v.versionId), ['1', '2', '3']);
    });

    test('a side whose clock reads before the cursor is read whole', () async {
      await save(there.db, {'id': 'missed', 'gender': 'male'});
      // The cursor a sync left when the peer's clock was a day ahead.
      final ahead =
          DateTime.now().toUtc().add(const Duration(days: 1)).toIso8601String();
      await here.db.setSyncCursor(
        peerUrl,
        remoteSince: ahead,
        localSince: ahead,
      );

      final r = await sync();

      expect(r['failure'], isNull);
      expect((await read(here.db, 'missed'))!['gender'], 'male');
    });
  });

  test("the merge rule decides with each server's own times", () {
    // A check that the integration above runs the rule under test, not
    // another: the same inputs straight through mergeResource.
    final t0 = DateTime.utc(2026);
    final merged = mergeResource(
      local: SyncSide(
        base: SyncVersion('1', t0, {'resourceType': 'Patient', ...start}),
        since: const [],
      ),
      remote: SyncSide(
        base: SyncVersion('1', t0, {'resourceType': 'Patient', ...start}),
        since: [
          SyncVersion(
            '2',
            t0.add(const Duration(minutes: 1)),
            {'resourceType': 'Patient', ...start, 'gender': 'other'},
          ),
        ],
      ),
    );
    expect(merged.json!['gender'], 'other');
  });
}

/// A [SyncEndpoint] that can answer in place of [inner] ([answer] returns a
/// reply) or act just before a request goes through ([before]).
class _Intercept implements SyncEndpoint {
  _Intercept(this.inner, this.answer, {this.before});

  final SyncEndpoint inner;
  final SyncReply? Function(String method, String path) answer;
  final Future<void> Function(String method, String path)? before;

  @override
  Uri get base => inner.base;

  @override
  Future<SyncReply> send(
    String method,
    String pathAndQuery, {
    Map<String, String>? headers,
    String? body,
  }) async {
    await before?.call(method, pathAndQuery);
    final canned = answer(method, pathAndQuery);
    if (canned != null) return canned;
    return inner.send(method, pathAndQuery, headers: headers, body: body);
  }
}

/// A peer that takes [allowed] writes and refuses every later one with
/// 503, counting each entry of a batch as one write: a server that goes
/// down partway through a run.
class _GoesDown implements SyncEndpoint {
  _GoesDown(this.inner, this.allowed);

  final SyncEndpoint inner;
  final int allowed;
  int _writes = 0;

  static const SyncReply _down =
      (status: 503, headers: <String, String>{}, body: 'down');

  @override
  Uri get base => inner.base;

  @override
  Future<SyncReply> send(
    String method,
    String pathAndQuery, {
    Map<String, String>? headers,
    String? body,
  }) async {
    if (method == 'PUT' || method == 'DELETE') {
      if (++_writes > allowed) return _down;
    }
    if (method != 'POST' || body == null) {
      return inner.send(method, pathAndQuery, headers: headers, body: body);
    }
    final bundle = jsonDecode(body) as Map<String, dynamic>;
    // A server that goes down during a transaction takes none of it.
    if (bundle['type'] == 'transaction') return _down;
    final entries = (bundle['entry'] as List).cast<Map<String, dynamic>>();
    final through = <Map<String, dynamic>>[];
    for (final e in entries) {
      if (++_writes > allowed) break;
      through.add(e);
    }
    var answered = <dynamic>[];
    if (through.isNotEmpty) {
      final reply = await inner.send(
        method,
        pathAndQuery,
        headers: headers,
        body: jsonEncode({...bundle, 'entry': through}),
      );
      answered = (jsonDecode(reply.body) as Map)['entry'] as List;
    }
    return (
      status: 200,
      headers: <String, String>{},
      body: jsonEncode({
        'resourceType': 'Bundle',
        'type': 'batch-response',
        'entry': [
          ...answered,
          for (var i = through.length; i < entries.length; i++)
            {
              'response': {'status': '503'},
            },
        ],
      }),
    );
  }
}

/// A disk with room for the request that starts a sync and none after it.
class _FillsUp implements DiskSpace {
  static const int _total = 64 * 1024 * 1024 * 1024;
  int _calls = 0;

  @override
  DiskUsage? measure(String path) =>
      (free: _calls++ == 0 ? _total : 0, total: _total);
}
