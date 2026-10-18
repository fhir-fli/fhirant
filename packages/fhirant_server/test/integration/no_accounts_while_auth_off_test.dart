import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/fhirant_server.dart'
    show AdminProvisioning, BackupService;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// Found on the phone run of REVIEW-2026-10-17 (2026-10-18, OnePlus CPH2749).
/// With authentication off (the app's Experimentation mode) every request
/// runs as a synthetic admin. Registration was already refused there
/// (REVIEW-2026-09-08 row 13: "anyone on the network could register the
/// account Secure mode later trusts as its administrator"), but two other
/// routes still changed accounts:
///
/// - `$restore` merged the backup's `users` (and OAuth client pins and the
///   other server tables). From the laptop, a backup holding an admin was
///   restored to the phone with no credential; the operator's switch to
///   Secure then found an admin, skipped the setup dialog, and the phone ran
///   Secure with the planted account as its only admin (its login 200, a
///   Patient search 200).
/// - `/admin/*` let the synthetic admin reset an existing account's password,
///   activate it, or change its role or scopes.
///
/// While authentication is off nothing over the network changes accounts: a
/// restore brings in FHIR resources only, and `/admin/*` is 403.
void main() {
  const passphrase = 'restore-probe-passphrase';

  /// A backup file holding Patient/p1, an admin `planted` and a pinned
  /// OAuth client, as an authenticated server's `$backup` writes it.
  Future<List<int>> plantedBackup() async {
    final source = await createTestServer();
    addTearDown(source.db.close);
    await source.db.saveResource(
      fhir.Patient(id: 'p1'.toFhirString),
    );
    await source.db.createUser(
      username: 'planted',
      passwordHash: 'h',
      salt: 's',
      role: 'admin',
    );
    await source.db.registerOAuthClient('app', 'https://evil.example/cb');
    final dir = await Directory.systemTemp.createTemp('planted-');
    addTearDown(() => dir.delete(recursive: true));
    final file = await BackupService.createFile(
      source.db,
      passphrase,
      '${dir.path}/b.sqlite',
    );
    return file.readAsBytes();
  }

  Future<Response> restore(
    Handler handler,
    List<int> bytes, {
    String? token,
  }) async =>
      handler(
        Request(
          'POST',
          Uri.parse(r'http://localhost:8080/$restore'),
          body: bytes,
          headers: {
            'x-forwarded-for': '127.0.0.1',
            'content-type': 'application/vnd.sqlite3',
            'x-backup-passphrase': passphrase,
            if (token != null) 'authorization': 'Bearer $token',
          },
        ),
      );

  test('authentication off: a restore brings resources, not accounts',
      () async {
    final bytes = await plantedBackup();
    final target = await createTestServer(devMode: true);
    addTearDown(target.db.close);

    final r = await restore(target.handler, bytes);
    expect(r.statusCode, 200, reason: await r.readAsString());

    expect(
      await target.db.getResource(fhir.R4ResourceType.Patient, 'p1'),
      isNotNull,
      reason: 'the record itself is restored',
    );
    expect(await target.db.getUserByUsername('planted'), isNull);
    expect(await AdminProvisioning.hasActiveAdmin(target.db), isFalse);
    expect(await target.db.getOAuthClientRedirect('app'), isNull);
  });

  test('control, authentication on: an admin restore merges accounts',
      () async {
    final bytes = await plantedBackup();
    final target = await createTestServer();
    addTearDown(target.db.close);
    final token = await issueTestToken(
      target.db,
      username: 'operator',
      role: 'admin',
      scopes: ['system/*.*'],
    );

    final r = await restore(target.handler, bytes, token: token);
    expect(r.statusCode, 200, reason: await r.readAsString());
    expect(await target.db.getUserByUsername('planted'), isNotNull);
    expect(
      await target.db.getOAuthClientRedirect('app'),
      'https://evil.example/cb',
    );
  });

  group('authentication off: /admin is refused', () {
    late FhirAntDb db;
    late Handler handler;
    late int userId;

    setUp(() async {
      final server = await createTestServer(devMode: true);
      db = server.db;
      handler = server.handler;
      userId = await db.createUser(
        username: 'existing',
        passwordHash: 'h',
        salt: 's',
        role: 'admin',
      );
      // A second admin, so the last-admin guard (409) does not stand in for
      // the refusal under test.
      await db.createUser(
        username: 'other',
        passwordHash: 'h',
        salt: 's',
        role: 'admin',
      );
    });

    tearDown(() => db.close());

    final routes = <(String, String, Map<String, dynamic>?)>[
      ('GET', '/admin/users', null),
      ('POST', '/admin/users/{id}/password', {'new_password': r'k7#Lm2$qZx9!'}),
      ('POST', '/admin/users/{id}/activate', null),
      ('POST', '/admin/users/{id}/deactivate', null),
      ('PUT', '/admin/users/{id}/role', {'role': 'clinician'}),
      (
        'PUT',
        '/admin/users/{id}/scopes',
        {
          'scopes': ['system/*.*'],
        }
      ),
      ('POST', '/admin/unlock/{id}', null),
    ];

    for (final (method, path, body) in routes) {
      test('$method $path is 403', () async {
        final r = await handler(
          testRequest(
            method,
            path.replaceAll('{id}', '$userId'),
            body: body == null ? null : jsonEncode(body),
            headers: {'content-type': 'application/json'},
          ),
        );
        expect(r.statusCode, 403, reason: await r.readAsString());
      });
    }

    test('the account is as it was', () async {
      for (final (method, path, body) in routes) {
        await handler(
          testRequest(
            method,
            path.replaceAll('{id}', '$userId'),
            body: body == null ? null : jsonEncode(body),
            headers: {'content-type': 'application/json'},
          ),
        );
      }
      final user = (await db.getUserByUsername('existing'))!;
      expect(user.passwordHash, 'h');
      expect(user.role, 'admin');
      expect(user.active, isTrue);
    });
  });
}
