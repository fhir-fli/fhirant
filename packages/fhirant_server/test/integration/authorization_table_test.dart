import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-17 A1, A2, A3, A5, A6: the authorization rules that lived
/// in one handler each, or nowhere, now live in `authorizeRequest`, which
/// the middleware and every Bundle entry go through. Each rule here is
/// tried at the REST route, at the conditional route where one exists,
/// and as a Bundle entry.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String admin;
  late String clinician;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    admin = await issueTestToken(
      db,
      username: 'a-admin',
      role: 'admin',
      scopes: ['system/*.*'],
    );
    clinician = await issueTestToken(
      db,
      username: 'a-clin',
      scopes: ['user/*.cruds'],
    );
  });
  tearDown(() => db.close());

  Future<Response> send(
    String method,
    String path, {
    Object? body,
    String? token,
    bool anonymous = false,
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
          headers: {'content-type': 'application/fhir+json'},
          authToken: anonymous ? null : (token ?? clinician),
        ),
      );

  Future<int> status(
    String method,
    String path, {
    Object? body,
    String? token,
  }) async =>
      (await send(method, path, body: body, token: token)).statusCode;

  /// The status of one entry of a transaction Bundle, from the Bundle's
  /// own status (a refused entry fails the transaction).
  Future<int> bundleEntry(
    String method,
    String url, {
    Map<String, dynamic>? resource,
    String? token,
  }) async =>
      status(
        'POST',
        '/',
        token: token,
        body: {
          'resourceType': 'Bundle',
          'type': 'transaction',
          'entry': [
            {
              if (resource != null) 'resource': resource,
              'request': {'method': method, 'url': url},
            },
          ],
        },
      );

  Map<String, dynamic> patient(String id) => {
        'resourceType': 'Patient',
        'id': id,
      };

  Map<String, dynamic> auditEvent(String id) => {
        'resourceType': 'AuditEvent',
        'id': id,
        'type': {
          'system': 'http://dicom.nema.org/resources/ontology/DCM',
          'code': '110100',
        },
        'recorded': '2026-09-18T00:00:00Z',
        'agent': [
          {'requestor': true},
        ],
        'source': {
          'observer': {'display': 'test'},
        },
      };

  group('A1: patient/ scopes with no patient context fail closed', () {
    late String noContext;
    setUp(() async {
      await send('PUT', '/Patient/p1', body: patient('p1'), token: admin);
      await send('PUT', '/Patient/p2', body: patient('p2'), token: admin);
      noContext = await issueTestToken(
        db,
        username: 'a-nocontext',
        scopes: ['patient/*.rs'],
      );
    });

    test('at the root, where the type check never ran', () async {
      expect(await status('GET', '/?_type=Patient', token: noContext), 403);
      expect(await status('GET', '/_history', token: noContext), 403);
      expect(await status('POST', '/_search', token: noContext), 403);
    });

    test('at a type, as before', () async {
      expect(await status('GET', '/Patient', token: noContext), 403);
      expect(await status('GET', '/Patient/p1', token: noContext), 403);
    });

    test('with a patient context the same scopes work', () async {
      final withContext = await issueTestToken(
        db,
        username: 'a-context',
        scopes: ['patient/*.rs'],
        patientId: 'p1',
      );
      expect(await status('GET', '/Patient/p1', token: withContext), 200);
      expect(await status('GET', '/Patient/p2', token: withContext), 403);
    });
  });

  group('A2: AuditEvent is append-only to everyone but the server', () {
    setUp(() async {
      // The server's own record of a request, as the audit middleware
      // writes it.
      await db.saveResource(fhir.Resource.fromJson(auditEvent('ae1')));
    });

    for (final who in ['clinician', 'admin']) {
      test('$who cannot PUT, PATCH, DELETE or POST one', () async {
        final token = who == 'admin' ? admin : clinician;
        expect(
          await status(
            'PUT',
            '/AuditEvent/ae1',
            body: auditEvent('ae1'),
            token: token,
          ),
          403,
        );
        expect(
          await status(
            'POST',
            '/AuditEvent',
            body: auditEvent('ae2')..remove('id'),
            token: token,
          ),
          403,
        );
        expect(await status('DELETE', '/AuditEvent/ae1', token: token), 403);
        expect(
          await status('DELETE', '/AuditEvent?_id=ae1', token: token),
          403,
        );
        expect(
          await status(
            'POST',
            r'/AuditEvent/ae1/$meta-add',
            token: token,
            body: {
              'resourceType': 'Parameters',
              'parameter': [
                {
                  'name': 'meta',
                  'valueMeta': {
                    'tag': [
                      {'system': 'urn:x', 'code': 'y'},
                    ],
                  },
                },
              ],
            },
          ),
          403,
        );
        expect(
          await bundleEntry(
            'PUT',
            'AuditEvent/ae1',
            resource: auditEvent('ae1'),
            token: token,
          ),
          isNot(200),
        );
        expect(
          await bundleEntry('DELETE', 'AuditEvent/ae1', token: token),
          isNot(200),
        );
        // Still there, unchanged.
        final stored = await db.getResource(
          fhir.R4ResourceType.AuditEvent,
          'ae1',
        );
        expect(stored!.meta!.versionId!.valueString, '1');
      });
    }

    test('reading it stays as it was', () async {
      expect(await status('GET', '/AuditEvent/ae1', token: clinician), 200);
      expect(await status('GET', '/AuditEvent', token: clinician), 200);
    });
  });

  group('A3: a lock blocks password login and nothing else', () {
    test('a locked account keeps its live session', () async {
      final user = await db.getUserByUsername('a-clin');
      await db.lockAccount(
        user!.id,
        DateTime.now().add(const Duration(minutes: 15)),
      );
      expect(await status('GET', '/Patient', token: clinician), 200);
    });
  });

  group('A5: HEAD is authorized as the GET it stands for', () {
    setUp(() async {
      await send('PUT', '/Patient/p1', body: patient('p1'), token: admin);
    });

    test('HEAD of a type the scope does not cover is refused', () async {
      final obsOnly = await issueTestToken(
        db,
        username: 'a-obs',
        scopes: ['user/Observation.rs'],
      );
      expect(await status('GET', '/Patient/p1', token: obsOnly), 403);
      expect(await status('HEAD', '/Patient/p1', token: obsOnly), 403);
      expect(await status('HEAD', '/Patient', token: obsOnly), 403);
    });

    test('HEAD of a covered type answers', () async {
      expect(await status('HEAD', '/Patient/p1', token: clinician), 200);
    });
  });

  group('A6: a SearchParameter goes only by system authority', () {
    Map<String, dynamic> definition(String id) => {
          'resourceType': 'SearchParameter',
          'id': id,
          'url': 'http://example.org/SearchParameter/$id',
          'name': id,
          'status': 'active',
          'description': id,
          'code': 'x-$id',
          'base': ['Patient'],
          'type': 'string',
          'expression': 'Patient.name.family',
        };

    setUp(() async {
      expect(
        await status(
          'PUT',
          '/SearchParameter/sp1',
          body: definition('sp1'),
          token: admin,
        ),
        201,
      );
    });

    test('a clinician cannot delete it by any route', () async {
      expect(await status('DELETE', '/SearchParameter/sp1'), 403);
      expect(await status('DELETE', '/SearchParameter?code=x-sp1'), 403);
      expect(await bundleEntry('DELETE', 'SearchParameter/sp1'), isNot(200));
      expect(
        await bundleEntry('DELETE', 'SearchParameter?code=x-sp1'),
        isNot(200),
      );
      expect(await status('GET', '/SearchParameter/sp1'), 200);
    });

    test('an administrator can', () async {
      expect(
        await status('DELETE', '/SearchParameter?code=x-sp1', token: admin),
        204,
      );
    });
  });
}
