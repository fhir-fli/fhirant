import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// Registered apps (REVIEW-2026-10-17 M1). OWASP ASVS 5.0.0 V10.4.1
/// (0x19-V10-OAuth-and-OIDC.md at tag v5.0.0, read 2026-11-22, verbatim):
/// "Verify that the authorization server validates redirect URIs based on
/// a client-specific allowlist of pre-registered URIs using exact string
/// comparison." Until 2026-11-22 a client_id nobody had seen was pinned to
/// the address its first sign-in named, and `http://evil.example/cb` got a
/// code. Loopback addresses keep a free port (RFC 8252 §7.3).
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String admin;

  const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
  final challenge = base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    final r = await handler(
      testRequest(
        'POST',
        '/auth/register',
        body: jsonEncode({'username': 'admin1', 'password': 'admin1pass12345'}),
      ),
    );
    admin = (jsonDecode(await r.readAsString()) as Map)['token'] as String;
  });

  tearDown(() => db.close());

  Future<(int, Map<String, dynamic>)> call(
    String method,
    String path, {
    Object? body,
    String? token,
  }) async {
    final r = await handler(
      testRequest(
        method,
        path,
        headers: {'content-type': 'application/json'},
        body: body == null ? null : jsonEncode(body),
        authToken: token ?? admin,
      ),
    );
    final text = await r.readAsString();
    return (
      r.statusCode,
      text.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(text) as Map<String, dynamic>,
    );
  }

  Future<(int, Map<String, dynamic>)> put(String id, Object body) =>
      call('PUT', '/admin/clients/$id', body: body);

  /// JSON authorize as admin1; the status and the body.
  Future<(int, Map<String, dynamic>)> authorize(
    String clientId,
    String redirect,
  ) async {
    final r = await handler(
      testRequest(
        'POST',
        '/auth/authorize',
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'response_type': 'code',
          'state': 'xyz',
          'aud': 'http://localhost:8080',
          'client_id': clientId,
          'redirect_uri': redirect,
          'scope': 'user/*.rs',
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
          'username': 'admin1',
          'password': 'admin1pass12345',
        }),
      ),
    );
    return (
      r.statusCode,
      jsonDecode(await r.readAsString()) as Map<String, dynamic>,
    );
  }

  Future<Map<String, dynamic>> tokens(String code, String redirect) async {
    final r = await handler(
      testRequest(
        'POST',
        '/auth/token',
        body: jsonEncode({
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': redirect,
          'client_id': 'scarab',
          'code_verifier': verifier,
        }),
      ),
    );
    final text = await r.readAsString();
    expect(r.statusCode, 200, reason: text);
    return jsonDecode(text) as Map<String, dynamic>;
  }

  test('an app nobody registered gets no code, and no redirect', () async {
    final (status, body) = await authorize('scarab', 'http://evil.example/cb');
    expect(status, 400, reason: '$body');
    expect(body.toString(), contains('not registered'));
    expect(body['code'], isNull);
  });

  test('register, list, change, remove', () async {
    var (s, b) = await put('scarab', {
      'name': 'Scarab',
      'redirect_uris': ['https://scarab.example/cb', 'http://127.0.0.1/cb'],
    });
    expect(s, 201, reason: '$b');
    expect(b['client_id'], 'scarab');
    expect(b['redirect_uris'], [
      'http://127.0.0.1/cb',
      'https://scarab.example/cb',
    ]);

    (s, b) = await call('GET', '/admin/clients');
    expect(s, 200);
    expect((b['apps'] as List).single['name'], 'Scarab');

    (s, b) = await put('scarab', {
      'name': 'Scarab EHR',
      'redirect_uris': ['https://scarab.example/cb'],
    });
    expect(s, 200, reason: 'a change, not a new app');
    expect(b['redirect_uris'], ['https://scarab.example/cb']);

    (s, b) = await call('DELETE', '/admin/clients/scarab');
    expect(s, 204);
    (s, b) = await call('DELETE', '/admin/clients/scarab');
    expect(s, 404);
    (s, b) = await call('GET', '/admin/clients');
    expect(b['apps'], isEmpty);
  });

  group('refused registrations', () {
    for (final (label, id, body) in [
      (
        'no name',
        'a',
        {
          'redirect_uris': ['https://a.example/cb'],
        }
      ),
      ('no addresses', 'a', {'name': 'A', 'redirect_uris': <String>[]}),
      (
        'javascript: address',
        'a',
        {
          'name': 'A',
          'redirect_uris': ['javascript:alert(1)'],
        }
      ),
      (
        'address with a fragment',
        'a',
        {
          'name': 'A',
          'redirect_uris': ['https://a.example/cb#x'],
        }
      ),
      (
        'relative address',
        'a',
        {
          'name': 'A',
          'redirect_uris': ['/cb'],
        }
      ),
      (
        'client_id outside VSCHAR',
        'caf%C3%A9',
        {
          'name': 'A',
          'redirect_uris': ['https://a.example/cb'],
        }
      ),
    ]) {
      test(label, () async {
        final (s, b) = await put(id, body);
        expect(s, 400, reason: '$b');
        expect(await db.getOAuthClients(), isEmpty);
      });
    }
  });

  test('only an administrator manages apps', () async {
    final clinician = await issueTestToken(
      db,
      username: 'clin',
      scopes: ['user/*.cruds'],
    );
    final (s, _) = await call('GET', '/admin/clients', token: clinician);
    expect(s, 403);
    final (p, _) = await call(
      'PUT',
      '/admin/clients/x',
      body: {
        'name': 'X',
        'redirect_uris': ['https://x.example/cb'],
      },
      token: clinician,
    );
    expect(p, 403);
    expect(await db.getOAuthClients(), isEmpty);
  });

  test(
      'a registered app signs in at its own address only; removed, its '
      'sessions end', () async {
    await put('scarab', {
      'name': 'Scarab',
      'redirect_uris': ['https://scarab.example/cb', 'http://127.0.0.1/cb'],
    });

    final (refused, _) = await authorize('scarab', 'https://evil.example/cb');
    expect(refused, 400, reason: 'not one of its addresses');
    final (loopback, lb) =
        await authorize('scarab', 'http://127.0.0.1:5123/cb');
    expect(loopback, 200, reason: 'RFC 8252 §7.3, any port: $lb');

    final (ok, body) = await authorize('scarab', 'https://scarab.example/cb');
    expect(ok, 200, reason: '$body');
    final session =
        await tokens(body['code'] as String, 'https://scarab.example/cb');
    final access = session['access_token'] as String;
    final (read, _) = await call('GET', '/Patient', token: access);
    expect(read, 200);

    // An unused code from before the removal goes with the app.
    final (_, pending) = await authorize('scarab', 'https://scarab.example/cb');

    final (removed, _) = await call('DELETE', '/admin/clients/scarab');
    expect(removed, 204);

    final (after, _) = await call('GET', '/Patient', token: access);
    expect(after, 401, reason: "the app's access token is refused");
    final refresh = await handler(
      testRequest(
        'POST',
        '/auth/token',
        body: jsonEncode({
          'grant_type': 'refresh_token',
          'refresh_token': session['refresh_token'],
        }),
      ),
    );
    expect(refresh.statusCode, 401);
    expect(await refresh.readAsString(), contains('invalid_grant'));
    expect(await db.getAuthorizationCode(pending['code'] as String), isNull);
    final (again, _) = await authorize('scarab', 'https://scarab.example/cb');
    expect(again, 400);

    // Control: the administrator's own session, from no app, still works.
    final (mine, _) = await call('GET', '/admin/clients');
    expect(mine, 200);
  });

  test('registering and removing an app is in the audit trail', () async {
    await put('scarab', {
      'name': 'Scarab',
      'redirect_uris': ['https://scarab.example/cb'],
    });
    await call('DELETE', '/admin/clients/scarab');

    final deadline = DateTime.now().add(const Duration(seconds: 5));
    var found = <fhir.AuditEvent>[];
    while (DateTime.now().isBefore(deadline)) {
      found = (await db.getResourcesByType(fhir.R4ResourceType.AuditEvent))
          .whereType<fhir.AuditEvent>()
          .where(
            (e) =>
                e.subtype?.any((c) => c.code?.valueString == '110129') ?? false,
          )
          .toList();
      if (found.length >= 2) break;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(found, hasLength(2));
    for (final e in found) {
      expect(
        e.agent.any((a) => a.who?.display?.valueString == 'admin1'),
        isTrue,
        reason: 'the administrator is named',
      );
    }
  });
}
