import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:test/test.dart';

import '../integration/test_helpers.dart';

/// What kind of event each request is recorded as: AuditEvent `type`,
/// `subtype` and `action`.
///
/// Every event used to be `type` DCM 110112 "Query" (REVIEW-2026-09-17
/// triage, "New finding, reproduced, not yet fixed"), a create and a failed
/// login included. The sources, read 2026-11-21:
/// - IHE BALP StructureDefinition JSON (IHE.BasicAudit.Create, Read,
///   Update, Delete, Query): `type` audit-event-type#rest; subtype
///   create / read or vread / update or patch / delete / search,
///   search-type or search-system; action C / R / U / D / E.
/// - R4B valuesets.json, CodeSystem restful-interaction 4.3.0: the codes
///   in [r4bRestfulInteraction]. `search-compartment` and `execute` are
///   not among them.
/// - IHE.IUA.71 (BALP package): a token request is type DCM 110114,
///   subtype urn:ihe:event-type-code#ITI-71, action E.
/// - DICOM PS3.15 A.5.3.10 Query, A.5.3.11 Security Alert, A.5.3.12 User
///   Authentication (EventActionCode "Shall be: E Execute" in each) and
///   PS3.16 CID 400, 401, 403 for the codes.
void main() {
  /// R4B CodeSystem restful-interaction, every code (valuesets.json).
  const r4bRestfulInteraction = {
    'read', 'vread', 'update', 'patch', 'delete', 'history',
    'history-instance', 'history-type', 'history-system', 'create',
    'search', 'search-type', 'search-system', 'capabilities',
    'transaction', 'batch', 'operation', //
  };
  const rest = 'http://terminology.hl7.org/CodeSystem/audit-event-type|rest';
  const dcm = 'http://dicom.nema.org/resources/ontology/DCM';
  const interaction = 'http://hl7.org/fhir/restful-interaction';

  late FhirAntDb db;
  late FhirAntServer server;
  late String admin;
  final seen = <String>{};

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
    server =
        FhirAntServer(db, breachedPasswords: null, jwtSecret: testJwtSecret);
    admin = await issueTestToken(
      db,
      username: 'adm',
      role: 'admin',
      scopes: ['system/*.*'],
    );
    await db.saveResource(
      fhir.Patient(id: fhir.FhirString('p1'), active: fhir.FhirBoolean(true)),
    );
    seen.clear();
  });

  tearDown(() => db.close());

  String coding(fhir.Coding? c) =>
      c == null ? '-' : '${c.system?.valueString}|${c.code?.valueString}';

  String describe(fhir.AuditEvent e) {
    final subtype = e.subtype?.isEmpty ?? true ? null : e.subtype!.first;
    return '${coding(e.type)} ${coding(subtype)} ${e.action?.valueString}';
  }

  /// The events [method] [path] added, as `type subtype action`.
  Future<List<String>> recorded(
    String method,
    String path, {
    String? body,
    String contentType = 'application/fhir+json',
  }) async {
    final handler = server.createHandler(server.createRouter());
    await handler(
      testRequest(
        method,
        path,
        authToken: admin,
        body: body,
        headers: {'content-type': contentType},
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await server.auditQueue.drain();
    final events = (await db.getResourcesByType(
      fhir.R4ResourceType.AuditEvent,
    ))
        .whereType<fhir.AuditEvent>()
        .where((e) => seen.add(e.id!.valueString!))
        .toList();
    return [for (final e in events) describe(e)];
  }

  String restEvent(String code, String action) =>
      '$rest $interaction|$code $action';

  test('each FHIR interaction is rest with its R4B code and BALP action',
      () async {
    final patient = jsonEncode({'resourceType': 'Patient', 'id': 'p1'});
    final cases = <(String, String, String?), String>{
      ('POST', '/Patient', jsonEncode({'resourceType': 'Patient'})):
          restEvent('create', 'C'),
      ('GET', '/Patient/p1', null): restEvent('read', 'R'),
      ('GET', '/Patient/p1/_history/1', null): restEvent('vread', 'R'),
      ('GET', '/Patient/p1/_history', null): restEvent('history-instance', 'R'),
      ('GET', '/Patient/_history', null): restEvent('history-type', 'R'),
      ('GET', '/_history', null): restEvent('history-system', 'R'),
      ('PUT', '/Patient/p1', patient): restEvent('update', 'U'),
      ('GET', '/Patient?name=x', null): restEvent('search-type', 'E'),
      ('GET', '/?_type=Patient', null): restEvent('search-system', 'E'),
      ('GET', '/Patient/p1/Observation', null): restEvent('search', 'E'),
      ('GET', r'/Patient/p1/$everything', null): restEvent('operation', 'E'),
      ('DELETE', '/Patient/p1', null): restEvent('delete', 'D'),
    };
    for (final MapEntry(key: (method, path, body), value: want)
        in cases.entries) {
      expect(
        await recorded(method, path, body: body),
        [want],
        reason: '$method $path',
      );
    }
  });

  test('a PATCH is rest / patch / U', () async {
    final events = await recorded(
      'PATCH',
      '/Patient/p1',
      body: jsonEncode([
        {'op': 'replace', 'path': '/active', 'value': false},
      ]),
      contentType: 'application/json-patch+json',
    );
    expect(events, [restEvent('patch', 'U')]);
  });

  test('a transaction is rest / transaction / E, its entry rest / create / C',
      () async {
    final events = await recorded(
      'POST',
      '/',
      body: jsonEncode({
        'resourceType': 'Bundle',
        'type': 'transaction',
        'entry': [
          {
            'resource': {'resourceType': 'Patient'},
            'request': {'method': 'POST', 'url': 'Patient'},
          },
        ],
      }),
    );
    expect(
      events,
      unorderedEquals([
        restEvent('transaction', 'E'),
        restEvent('create', 'C'),
      ]),
    );
  });

  test('a path that is no FHIR interaction is rest with no subtype', () async {
    expect(await recorded('GET', '/NotAType'), ['$rest - R']);
  });

  test('every rest subtype recorded is an R4B restful-interaction code',
      () async {
    for (final (method, path) in [
      ('GET', '/Patient/p1'),
      ('GET', '/Patient/p1/Observation'),
      ('GET', r'/Patient/p1/$everything'),
      ('GET', '/Patient/p1/_history'),
    ]) {
      for (final event in await recorded(method, path)) {
        final code = event.split(' ')[1].split('|').last;
        expect(r4bRestfulInteraction, contains(code), reason: event);
      }
    }
  });

  test('login and logout are DCM User Authentication, action E', () async {
    final login = jsonEncode({'username': 'adm', 'password': 'wrong'});
    expect(
      await recorded(
        'POST',
        '/auth/login',
        body: login,
        contentType: 'application/json',
      ),
      ['$dcm|110114 $dcm|110122 E'],
    );
    for (final path in ['/auth/logout', '/auth/revoke']) {
      expect(
        await recorded(
          'POST',
          path,
          body: '{}',
          contentType: 'application/json',
        ),
        ['$dcm|110114 $dcm|110123 E'],
        reason: path,
      );
    }
    expect(
      await recorded(
        'POST',
        '/auth/authorize',
        body: 'username=adm&password=wrong',
        contentType: 'application/x-www-form-urlencoded',
      ),
      ['$dcm|110114 $dcm|110122 E'],
    );
  });

  test('the token endpoint is IUA ITI-71: DCM 110114, action E', () async {
    expect(
      await recorded(
        'POST',
        '/auth/token',
        body: 'grant_type=refresh_token&refresh_token=x',
        contentType: 'application/x-www-form-urlencoded',
      ),
      ['$dcm|110114 urn:ihe:event-type-code|ITI-71 E'],
    );
  });

  test('account changes are DCM Security Alert, action E', () async {
    const userChanged = '$dcm|110113 $dcm|110137 E';
    for (final (method, path, body) in [
      ('POST', '/auth/password', '{"old_password":"a","new_password":"b"}'),
      ('POST', '/auth/register', '{"username":"u2","password":"x"}'),
      ('POST', '/auth/claim', '{"username":"u2","password":"x"}'),
      ('POST', '/admin/unlock/1', '{}'),
      ('POST', '/admin/users/1/password', '{"password":"x"}'),
      ('POST', '/admin/users/1/approve', '{}'),
      ('POST', '/admin/users/1/deactivate', '{}'),
      ('POST', '/admin/users/1/activate', '{}'),
      ('PUT', '/admin/users/1/scopes', '{"scopes":[]}'),
    ]) {
      expect(
        await recorded(
          method,
          path,
          body: body,
          contentType: 'application/json',
        ),
        [userChanged],
        reason: '$method $path',
      );
    }
    expect(
      await recorded(
        'PUT',
        '/admin/users/1/role',
        body: '{"role":"admin"}',
        contentType: 'application/json',
      ),
      ['$dcm|110113 $dcm|110136 E'],
    );
  });

  test('reading account routes is DCM Query, no subtype, action E', () async {
    for (final path in ['/admin/users', '/auth/status', '/auth/authorize']) {
      expect(
        await recorded('GET', path),
        ['$dcm|110112 - E'],
        reason: path,
      );
    }
  });
}
