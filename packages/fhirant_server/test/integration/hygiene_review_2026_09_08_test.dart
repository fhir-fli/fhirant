import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/fhirant_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-08 §7 item 5 (hygiene) at the HTTP surface: rows 18, 20,
/// 31, 32, 39, 40, 43, 45, 46 and 47. Each test names its row.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String admin;
  late String clinician;
  late String exportDir;

  setUp(() async {
    exportDir = '${Directory.systemTemp.path}/fhirant_hygiene_'
        '${DateTime.now().microsecondsSinceEpoch}';
    final server = await createTestServer(exportDir: exportDir);
    db = server.db;
    handler = server.handler;
    admin = await issueTestToken(
      db,
      username: 'hyg-admin',
      role: 'admin',
      scopes: ['system/*.*'],
    );
    clinician = await issueTestToken(
      db,
      username: 'hyg-clin',
      scopes: ['user/*.cruds'],
    );
  });

  tearDown(() async {
    await db.close();
    final dir = Directory(exportDir);
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  Future<Map<String, dynamic>> json(Response r, [int? status]) async {
    final text = await r.readAsString();
    if (status != null) expect(r.statusCode, status, reason: text);
    return jsonDecode(text) as Map<String, dynamic>;
  }

  Future<Response> send(
    String method,
    String path, {
    Object? body,
    String? token,
    Map<String, String>? headers,
  }) async =>
      handler(
        testRequest(
          method,
          path,
          body: body == null
              ? null
              : body is String
                  ? body
                  : jsonEncode(body),
          authToken: token,
          headers: {
            if (body != null) 'content-type': 'application/fhir+json',
            ...?headers,
          },
        ),
      );

  Map<String, dynamic> subscription(String channelType) => {
        'resourceType': 'Subscription',
        'status': 'requested',
        'reason': 'test',
        'criteria': 'Patient?active=true',
        'channel': {
          'type': channelType,
          if (channelType == 'rest-hook') 'endpoint': 'http://10.0.0.5/hook',
          if (channelType == 'rest-hook') 'payload': 'application/fhir+json',
        },
      };

  /// Waits for the fire-and-forget audit writes to land: at least [atLeast]
  /// events, or the timeout.
  Future<List<fhir.AuditEvent>> auditEvents({int atLeast = 1}) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    var events = <fhir.AuditEvent>[];
    while (DateTime.now().isBefore(deadline)) {
      final all = await db.getResourcesByType(fhir.R4ResourceType.AuditEvent);
      events = all.whereType<fhir.AuditEvent>().toList();
      if (events.length >= atLeast) return events;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    return events;
  }

  group('row 18: a rest-hook Subscription is system-level', () {
    test('a clinician with user/*.cruds is refused with an OperationOutcome',
        () async {
      final r = await send(
        'POST',
        '/Subscription',
        body: subscription('rest-hook'),
        token: clinician,
      );
      final body = await json(r, 403);
      expect(body['resourceType'], 'OperationOutcome');
      expect(r.headers['content-type'], contains('application/fhir+json'));
      final stored =
          await db.getResourcesByType(fhir.R4ResourceType.Subscription);
      expect(stored, isEmpty, reason: 'nothing was stored');
    });

    test('the same clinician may create a websocket Subscription', () async {
      final r = await send(
        'POST',
        '/Subscription',
        body: subscription('websocket'),
        token: clinician,
      );
      expect(r.statusCode, 201, reason: await r.readAsString());
    });

    test('an admin with system/*.* may create the rest-hook', () async {
      final r = await send(
        'POST',
        '/Subscription',
        body: subscription('rest-hook'),
        token: admin,
      );
      expect(r.statusCode, 201, reason: await r.readAsString());
    });

    test(
        'a PUT that turns a websocket Subscription into a rest-hook is '
        'refused for the clinician', () async {
      final created = await json(
        await send(
          'POST',
          '/Subscription',
          body: subscription('websocket'),
          token: clinician,
        ),
        201,
      );
      final id = created['id'] as String;
      final r = await send(
        'PUT',
        '/Subscription/$id',
        body: {...subscription('rest-hook'), 'id': id},
        token: clinician,
      );
      expect(r.statusCode, 403, reason: await r.readAsString());
    });
  });

  test('row 20: smart-configuration names no registration_endpoint', () async {
    final body = await json(
      await send('GET', '/.well-known/smart-configuration'),
      200,
    );
    expect(body.containsKey('registration_endpoint'), isFalse);
    expect(body['token_endpoint'], contains('/auth/token'));
  });

  group('row 31: the CapabilityStatement says what is configured', () {
    test('cors is false when no origin is configured', () async {
      final body = await json(await send('GET', '/metadata'), 200);
      final rest = (body['rest'] as List).first as Map<String, dynamic>;
      final security = rest['security'] as Map<String, dynamic>;
      expect(security['cors'], isFalse);
    });

    test(
        "the fhirpath operation is this server's own definition, not a "
        'canonical R4B does not publish', () async {
      final body = await json(await send('GET', '/metadata'), 200);
      final rest = (body['rest'] as List).first as Map<String, dynamic>;
      final ops = (rest['operation'] as List).cast<Map<String, dynamic>>();
      final fhirpath = ops.firstWhere((o) => o['name'] == 'fhirpath');
      expect(
        fhirpath['definition'],
        isNot(contains('hl7.org/fhir/OperationDefinition/Resource-fhirpath')),
      );
      expect(
        fhirpath['definition'],
        'http://fhirant.fhir-fli.dev/OperationDefinition/fhirpath',
      );
    });
  });

  group('row 32: a parameter that does not parse is 400, not ignored', () {
    setUp(() async {
      await db.saveResource(fhir.Patient(id: 'p32'.toFhirString));
    });

    test(r'$everything _since', () async {
      final r = await send(
        'GET',
        r'/Patient/p32/$everything?_since=yesterday',
        token: admin,
      );
      final body = await json(r, 400);
      expect(body['resourceType'], 'OperationOutcome');
      final ok = await send(
        'GET',
        r'/Patient/p32/$everything?_since=2020-01-01T00:00:00Z',
        token: admin,
      );
      expect(ok.statusCode, 200);
    });

    for (final path in [
      '/Patient/p32/_history?_since=yesterday',
      '/Patient/_history?_at=yesterday',
      '/_history?_since=yesterday',
    ]) {
      test('history $path', () async {
        final r = await send('GET', path, token: admin);
        final body = await json(r, 400);
        expect(body['resourceType'], 'OperationOutcome');
      });
    }

    test('history with a parseable _since still answers', () async {
      final r = await send(
        'GET',
        '/Patient/p32/_history?_since=2020-01-01T00:00:00Z',
        token: admin,
      );
      expect(r.statusCode, 200, reason: await r.readAsString());
    });

    test(r'$fhirpath with an expression that does not parse', () async {
      final r = await send(
        'POST',
        r'/$fhirpath?expression=' + Uri.encodeQueryComponent('name.given('),
        body: {'resourceType': 'Patient', 'id': 'x'},
        token: admin,
      );
      final body = await json(r, 400);
      expect(body['resourceType'], 'OperationOutcome');
      expect(
        (body['issue'] as List).first['code'],
        'invalid',
      );
    });

    test(r'$cql with CQL that does not translate', () async {
      final r = await send(
        'POST',
        r'/$cql',
        body: {
          'resourceType': 'Parameters',
          'parameter': [
            {'name': 'cql', 'valueString': 'define X: ((('},
          ],
        },
        token: admin,
      );
      final body = await json(r, 400);
      expect(body['resourceType'], 'OperationOutcome');
    });
  });

  group('row 39: cancelling a running export leaves the row to the worker', () {
    test('DELETE on an in_progress job: 202, row kept as cancelled', () async {
      // A job row as the worker would have left it mid-run; no worker is
      // attached to it, which is the state the handler must not assume away.
      await db.createExportJob(
        jobId: '11111111-2222-4333-8444-555555555555',
        status: 'in_progress',
        requestUrl: r'http://localhost/$export',
        transactionTime: DateTime.now().toUtc(),
        exportLevel: 'system',
      );
      final dir = Directory('$exportDir/11111111-2222-4333-8444-555555555555')
        ..createSync(recursive: true);
      File('${dir.path}/Patient.ndjson').writeAsStringSync('{}\n');

      final r = await send(
        'DELETE',
        r'/$export-poll-status/11111111-2222-4333-8444-555555555555',
        token: admin,
      );
      expect(r.statusCode, 202, reason: await r.readAsString());

      final job = await db.getExportJob('11111111-2222-4333-8444-555555555555');
      expect(job, isNotNull, reason: 'the row is kept for the worker');
      expect(job!.status, 'cancelled');
      expect(job.completedAt, isNotNull, reason: 'the sweep needs a time');
      expect(dir.existsSync(), isTrue, reason: 'the worker deletes its own');

      // The sweep's query sees it as finished.
      final finished = await db.finishedExportJobsBefore(
        DateTime.now().toUtc().add(const Duration(hours: 1)),
      );
      expect(
        finished.map((j) => j.jobId),
        contains('11111111-2222-4333-8444-555555555555'),
      );
    });

    test('DELETE on a completed job removes row and files at once', () async {
      await db.createExportJob(
        jobId: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
        status: 'completed',
        requestUrl: r'http://localhost/$export',
        transactionTime: DateTime.now().toUtc(),
        exportLevel: 'system',
      );
      final dir = Directory('$exportDir/aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee')
        ..createSync(recursive: true);
      final r = await send(
        'DELETE',
        r'/$export-poll-status/aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
        token: admin,
      );
      expect(r.statusCode, 202);
      expect(
        await db.getExportJob('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'),
        isNull,
      );
      expect(dir.existsSync(), isFalse);
    });
  });

  group('row 40: patient-level export writes compartment members', () {
    Future<Map<String, dynamic>> runExport(String path) async {
      final kick = await send(
        'GET',
        path,
        token: admin,
        headers: {'prefer': 'respond-async'},
      );
      expect(kick.statusCode, 202, reason: await kick.readAsString());
      final jobId = kick.headers['content-location']!.split('/').last;
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline)) {
        final poll = await send(
          'GET',
          '/\$export-poll-status/$jobId',
          token: admin,
        );
        if (poll.statusCode == 200) return json(poll);
        expect(poll.statusCode, 202, reason: await poll.readAsString());
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      fail('export $jobId did not complete');
    }

    Future<List<String>> idsIn(
      Map<String, dynamic> manifest,
      String type,
    ) async {
      final output = (manifest['output'] as List).cast<Map<String, dynamic>>();
      final entry = output.where((o) => o['type'] == type).toList();
      if (entry.isEmpty) return const [];
      final url = entry.single['url'] as String;
      final r = await send('GET', Uri.parse(url).path, token: admin);
      final text = await r.readAsString();
      expect(r.statusCode, 200, reason: text);
      final lines = const LineSplitter().convert(text);
      return lines
          .map((l) => (jsonDecode(l) as Map<String, dynamic>)['id'] as String)
          .toList();
    }

    setUp(() async {
      await db.saveResource(fhir.Patient(id: 'pp1'.toFhirString));
      await db.saveResource(fhir.Patient(id: 'pp2'.toFhirString));
      final code = fhir.CodeableConcept(
        coding: [fhir.Coding(code: '8480-6'.toFhirCode)],
      );
      await db.saveResource(
        fhir.Observation(
          id: 'obs-of-pp1'.toFhirString,
          status: fhir.ObservationStatus.final_,
          code: code,
          subject: fhir.Reference(reference: 'Patient/pp1'.toFhirString),
        ),
      );
      await db.saveResource(
        fhir.Observation(
          id: 'obs-performed-by-pp2'.toFhirString,
          status: fhir.ObservationStatus.final_,
          code: code,
          performer: [
            fhir.Reference(reference: 'Patient/pp2'.toFhirString),
          ],
        ),
      );
      // No subject, no performer: in no patient's compartment.
      await db.saveResource(
        fhir.Observation(
          id: 'obs-of-nobody'.toFhirString,
          status: fhir.ObservationStatus.final_,
          code: code,
        ),
      );
      // A compartment type with a subject that is not a Patient.
      await db.saveResource(
        fhir.Observation(
          id: 'obs-of-a-device'.toFhirString,
          status: fhir.ObservationStatus.final_,
          code: code,
          subject: fhir.Reference(reference: 'Device/d1'.toFhirString),
        ),
      );
    });

    test('an Observation with no patient is not written', () async {
      final manifest = await runExport(r'/Patient/$export');
      expect(
        await idsIn(manifest, 'Observation'),
        unorderedEquals(['obs-of-pp1', 'obs-performed-by-pp2']),
      );
      expect(
        await idsIn(manifest, 'Patient'),
        unorderedEquals(['pp1', 'pp2']),
        reason: 'every Patient is in its own compartment',
      );
    });

    test('with _type the same membership applies', () async {
      final manifest = await runExport(r'/Patient/$export?_type=Observation');
      final output = (manifest['output'] as List).cast<Map<String, dynamic>>();
      expect(output.map((o) => o['type']), ['Observation']);
      expect(
        await idsIn(manifest, 'Observation'),
        unorderedEquals(['obs-of-pp1', 'obs-performed-by-pp2']),
      );
    });

    test('a _typeFilter narrows within the members', () async {
      final manifest = await runExport(
        r'/Patient/$export?_type=Observation&_typeFilter='
        '${Uri.encodeQueryComponent('Observation?subject=Patient/pp1')}',
      );
      expect(await idsIn(manifest, 'Observation'), ['obs-of-pp1']);
    });

    test('the system-level export still writes every Observation', () async {
      final manifest = await runExport(r'/$export?_type=Observation');
      expect(
        await idsIn(manifest, 'Observation'),
        unorderedEquals([
          'obs-of-pp1',
          'obs-performed-by-pp2',
          'obs-of-nobody',
          'obs-of-a-device',
        ]),
      );
    });
  });

  test(r'row 43: $everything pages, read per type, cover the compartment once',
      () async {
    await db.saveResource(fhir.Patient(id: 'pe'.toFhirString));
    final code = fhir.CodeableConcept(
      coding: [fhir.Coding(code: '8480-6'.toFhirCode)],
    );
    for (var i = 0; i < 5; i++) {
      await db.saveResource(
        fhir.Observation(
          id: 'pe-obs-$i'.toFhirString,
          status: fhir.ObservationStatus.final_,
          code: code,
          subject: fhir.Reference(reference: 'Patient/pe'.toFhirString),
        ),
      );
      await db.saveResource(
        fhir.Condition(
          id: 'pe-cond-$i'.toFhirString,
          subject: fhir.Reference(reference: 'Patient/pe'.toFhirString),
        ),
      );
    }
    final seen = <String>[];
    var path = r'/Patient/pe/$everything?_count=4';
    var pages = 0;
    while (true) {
      final body = await json(await send('GET', path, token: admin), 200);
      pages++;
      for (final e in (body['entry'] as List).cast<Map<String, dynamic>>()) {
        final res = e['resource'] as Map<String, dynamic>;
        seen.add('${res['resourceType']}/${res['id']}');
      }
      final next = (body['link'] as List)
          .cast<Map<String, dynamic>>()
          .where((l) => l['relation'] == 'next')
          .toList();
      if (next.isEmpty) break;
      final uri = Uri.parse(next.single['url'] as String);
      path = '${uri.path}?${uri.query}';
    }
    expect(pages, 3);
    expect(seen.length, 11);
    expect(seen.toSet().length, 11, reason: 'no resource twice');
    expect(seen.first, 'Patient/pe');
    // Within the pages, types in name order and ids sorted: Condition before
    // Observation, and the page cut does not reorder.
    expect(
      seen.sublist(1, 6),
      [for (var i = 0; i < 5; i++) 'Condition/pe-cond-$i'],
    );
    expect(
      seen.sublist(6),
      [for (var i = 0; i < 5; i++) 'Observation/pe-obs-$i'],
    );
  });

  group('rows 45 and 46: what the audit trail records', () {
    test('GET /health is not audited; a read after it is', () async {
      await db.saveResource(fhir.Patient(id: 'pa'.toFhirString));
      expect((await send('GET', '/health')).statusCode, 200);
      expect((await send('GET', '/Patient/pa', token: admin)).statusCode, 200);
      // Writes are queued in order: once the read's event is there, a
      // health event would be there too.
      final events = await auditEvents();
      expect(events, hasLength(1));
      final entityRefs = events
          .expand((e) => e.entity ?? const <fhir.AuditEventEntity>[])
          .map((en) => en.what?.reference?.valueString)
          .toList();
      expect(entityRefs, contains('Patient/pa'));
      expect(entityRefs.where((r) => r?.contains('health') ?? false), isEmpty);
    });

    test('POST _search is action R / search, an operation is E / execute',
        () async {
      await db.saveResource(fhir.Patient(id: 'pb'.toFhirString));
      expect(
        (await send(
          'POST',
          '/Patient/_search',
          body: 'name=x',
          token: admin,
          headers: {'content-type': 'application/x-www-form-urlencoded'},
        ))
            .statusCode,
        200,
      );
      expect(
        (await send('GET', r'/Patient/pb/$everything', token: admin))
            .statusCode,
        200,
      );
      final events = await auditEvents(atLeast: 2);
      final byAction = {
        for (final e in events)
          e.action?.valueString: e.subtype?.first.code?.valueString,
      };
      expect(byAction['R'], 'search');
      expect(byAction['E'], 'execute');
      expect(byAction.containsKey('C'), isFalse, reason: 'nothing was created');
    });

    test('auth/login is not turned into a resource reference', () async {
      final r = await send(
        'POST',
        '/auth/login',
        body: {'username': 'hyg-admin', 'password': 'wrong'},
        token: admin,
      );
      expect(r.statusCode, 401);
      final events = await auditEvents();
      expect(events, hasLength(1));
      final refs = events
          .expand((e) => e.entity ?? const <fhir.AuditEventEntity>[])
          .map((en) => en.what?.reference?.valueString)
          .whereType<String>()
          .toList();
      expect(refs, isNot(contains('auth/login')));
    });
  });

  group('row 47: an escaping exception and the request log', () {
    test('a handler that throws answers a 500 OperationOutcome', () async {
      final store = FhirAntDb(NativeDatabase.memory());
      await store.initialize();
      addTearDown(store.close);
      final server = FhirAntServer(store, jwtSecret: testJwtSecret);
      final router = Router()
        ..get('/boom', (Request _) => throw StateError('secret detail'));
      final pipeline = server.createHandler(router);
      final token = await issueTestToken(store, role: 'admin');
      final r = await pipeline(testRequest('GET', '/boom', authToken: token));
      final body = await json(r, 500);
      expect(body['resourceType'], 'OperationOutcome');
      expect(r.headers['content-type'], contains('application/fhir+json'));
      expect(jsonEncode(body), isNot(contains('secret detail')));
    });

    test('the request-log entry carries the redacted path', () async {
      final store = FhirAntDb(NativeDatabase.memory());
      await store.initialize();
      addTearDown(store.close);
      final server = FhirAntServer(store, jwtSecret: testJwtSecret);
      final pipeline = server.createHandler(server.createRouter());
      final token = await issueTestToken(store, role: 'admin');
      final entries = <RequestLogEntry>[];
      final sub = server.requestLog.listen(entries.add);
      addTearDown(sub.cancel);
      await pipeline(
        testRequest(
          'GET',
          '/Patient/secret-id?name=Smith&_count=5',
          authToken: token,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(entries, hasLength(1));
      expect(
        entries.single.path,
        '/Patient/{id}?name=[redacted]&_count=[redacted]',
      );
    });
  });
}
