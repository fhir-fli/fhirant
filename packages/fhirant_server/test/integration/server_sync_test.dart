import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
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

  setUp(() async {
    here = await createTestServer(devMode: true);
    there = await createTestServer(devMode: true);
    peerSocket = await shelf_io.serve(
      there.handler,
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

  /// Runs `$sync` on [here] against the peer and returns the finished
  /// status as name → values.
  Future<Map<String, List<Object?>>> sync({String? token}) async {
    final kick = await here.handler(
      testRequest(
        'POST',
        r'/$sync',
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
      final status = await here.handler(testRequest('GET', r'/$sync-status'));
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

    // Each side gets the other's resource, and each resource gains
    // meta.source on both sides (a version on its first server too).
    expect(count(r, 'writtenToPeer'), 2);
    expect(count(r, 'writtenHere'), 2);
    expect(r['failure'], isNull);
    expect((await read(there.db, 'only-here'))!['gender'], 'male');
    expect((await read(here.db, 'only-there'))!['gender'], 'female');
    // meta.source names the server each was first saved on.
    expect(
      (await read(here.db, 'only-there'))!['meta']['source'],
      peerUrl,
    );
    expect(
      (await read(there.db, 'only-here'))!['meta']['source'],
      'http://localhost:8080',
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
    /// The peer, failing every write after [allowed] writes went through.
    SyncClient failingPeer(int allowed) {
      var writes = 0;
      return SyncClient(
        _Intercept(RemoteEndpoint(Uri.parse(peerUrl)), (method, path) {
          if (method != 'PUT' && method != 'DELETE') return null;
          writes++;
          return writes > allowed
              ? (status: 503, headers: <String, String>{}, body: 'down')
              : null;
        }),
      );
    }

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
        localBase: 'http://localhost:8080',
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
        localBase: 'http://localhost:8080',
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
