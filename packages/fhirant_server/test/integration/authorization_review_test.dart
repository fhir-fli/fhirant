import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// The authorization findings of REVIEW-2026-09-06.md, §1, as regression
/// tests. Every test here was first a probe that FAILED against the code
/// before the fix (`tool/review_2026-09-06/probes/OUTPUT.txt`); the
/// expectation is the specification's, and the code was changed to meet it.
void main() {
  late FhirAntDb db;
  late Handler handler;

  const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
  final challenge =
      base64Url.encode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll(
            '=',
            '',
          );

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
  });

  tearDown(() async {
    await db.close();
  });

  /// The body, decoded, after asserting the status. A shelf body can be
  /// read once, so the status reason and the decode share one read.
  Future<Map<String, dynamic>> json(Response r, [int? status]) async {
    final text = await r.readAsString();
    if (status != null) expect(r.statusCode, status, reason: text);
    return jsonDecode(text) as Map<String, dynamic>;
  }

  Future<String> registerAdmin() async {
    final r = await handler(
      testRequest(
        'POST',
        '/auth/register',
        body: jsonEncode({'username': 'admin1', 'password': 'admin1pass12345'}),
      ),
    );
    return (await json(r, 201))['token'] as String;
  }

  Future<void> register(
    String adminToken,
    String username, {
    String role = 'readonly',
    List<String>? scopes,
    String? patient,
  }) async {
    final r = await handler(
      testRequest(
        'POST',
        '/auth/register',
        body: jsonEncode({
          'username': username,
          'password': '${username}pass12345',
          'role': role,
          if (scopes != null) 'scopes': scopes,
          if (patient != null) 'patient': patient,
        }),
        authToken: adminToken,
      ),
    );
    await json(r, 201);
  }

  /// Runs the authorization-code flow (JSON authorize, then the token
  /// endpoint) and returns the token response body.
  Future<Map<String, dynamic>> oauth(
    String username,
    String scope, {
    String clientId = 'app',
    String redirect = 'http://localhost/cb',
  }) async {
    final auth = await handler(
      testRequest(
        'POST',
        '/auth/authorize',
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'response_type': 'code',
          'client_id': clientId,
          'redirect_uri': redirect,
          'scope': scope,
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
          'username': username,
          'password': '${username}pass12345',
        }),
      ),
    );
    final code = (await json(auth, 200))['code'] as String;
    final tok = await handler(
      testRequest(
        'POST',
        '/auth/token',
        body: jsonEncode({
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': redirect,
          'client_id': clientId,
          'code_verifier': verifier,
        }),
      ),
    );
    return json(tok, 200);
  }

  group(
      'finding 1: the OAuth grant is the request intersected with the '
      'account', () {
    test('a readonly account asking for system/*.* gets user/*.rs', () async {
      final admin = await registerAdmin();
      await register(admin, 'readonly1');
      final tok = await oauth('readonly1', 'system/*.* user/*.cruds');
      expect(tok['scope'], 'user/*.rs');
      final create = await handler(
        testRequest(
          'POST',
          '/Patient',
          body: '{"resourceType":"Patient"}',
          authToken: tok['access_token'] as String,
        ),
      );
      expect(create.statusCode, 403);
    });

    test('a request wholly outside the grant is refused as invalid_scope',
        () async {
      final admin = await registerAdmin();
      await register(admin, 'readonly1');
      final auth = await handler(
        testRequest(
          'POST',
          '/auth/authorize',
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'response_type': 'code',
            'client_id': 'app',
            'redirect_uri': 'http://localhost/cb',
            'scope': 'system/*.*',
            'code_challenge': challenge,
            'code_challenge_method': 'S256',
            'username': 'readonly1',
            'password': 'readonly1pass12345',
          }),
        ),
      );
      expect(auth.statusCode, 400);
      expect((await json(auth))['error'], 'invalid_scope');
    });

    test('a refresh narrows to what the account holds now', () async {
      final admin = await registerAdmin();
      await register(admin, 'clin1', role: 'clinician');
      final tok = await oauth('clin1', 'user/*.*');
      // Downgrade the account behind the token's back.
      final user = await db.getUserByUsername('clin1');
      await db.customStatement(
        "UPDATE users SET scopes = '[\"user/*.rs\"]' WHERE id = ?",
        [user!.id],
      );
      final refreshed = await handler(
        testRequest(
          'POST',
          '/auth/token',
          body: jsonEncode({
            'grant_type': 'refresh_token',
            'refresh_token': tok['refresh_token'],
          }),
        ),
      );
      expect(refreshed.statusCode, 200);
      expect((await json(refreshed))['scope'], 'user/*.rs');
    });
  });

  group('finding 8: standard SMART scopes', () {
    test(
        'openid fhirUser launch/patient beside a resource scope yield a '
        'usable token', () async {
      await registerAdmin();
      final tok = await oauth('admin1', 'openid fhirUser user/*.rs');
      final r = await handler(
        testRequest(
          'GET',
          '/Patient',
          authToken: tok['access_token'] as String,
        ),
      );
      expect(r.statusCode, 200, reason: await r.readAsString());
      // The response says what was granted; the token claim holds only the
      // resource scope.
      expect(tok['scope'], 'openid fhirUser user/*.rs');
      final payload =
          JwtService(testJwtSecret).verifyToken(tok['access_token'] as String);
      expect(payload!['scope'], 'user/*.rs');
    });

    test('the configuration advertises only what is served', () async {
      final r = await handler(
        testRequest('GET', '/.well-known/smart-configuration'),
      );
      final body = await json(r);
      expect(
        body.containsKey('issuer'),
        isFalse,
        reason: 'no OpenID Connect, so no issuer',
      );
      expect(body['scopes_supported'], isNot(contains('openid')));
      expect(body['code_challenge_methods_supported'], ['S256']);
      expect(body['capabilities'], contains('client-public'));
    });
  });

  group('finding 10: PKCE and the redirect pin', () {
    test('an authorize request without S256 PKCE is refused', () async {
      await registerAdmin();
      for (final pkce in [
        <String, String>{},
        {'code_challenge': challenge, 'code_challenge_method': 'plain'},
      ]) {
        final auth = await handler(
          testRequest(
            'POST',
            '/auth/authorize',
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'response_type': 'code',
              'client_id': 'app',
              'redirect_uri': 'http://localhost/cb',
              'scope': 'user/*.rs',
              ...pkce,
              'username': 'admin1',
              'password': 'admin1pass12345',
            }),
          ),
        );
        expect(auth.statusCode, 400, reason: '$pkce');
        expect((await json(auth))['error'], 'invalid_request');
      }
    });

    test('a client_id keeps the redirect_uri it first authorized with',
        () async {
      await registerAdmin();
      await oauth('admin1', 'user/*.rs', redirect: 'https://app.example/cb');
      final other = await handler(
        testRequest(
          'GET',
          '/auth/authorize?response_type=code&client_id=app'
              '&redirect_uri=https://evil.example/cb&scope=user/*.rs'
              '&code_challenge=$challenge&code_challenge_method=S256',
        ),
      );
      // Refused, and NOT redirected: RFC 6749 §3.1.2.4.
      expect(other.statusCode, 400);
      expect(other.headers['location'], isNull);
    });

    test('a loopback redirect may change its port', () async {
      await registerAdmin();
      await oauth('admin1', 'user/*.rs', redirect: 'http://127.0.0.1:4000/cb');
      final tok = await oauth(
        'admin1',
        'user/*.rs',
        redirect: 'http://127.0.0.1:5123/cb',
      );
      expect(tok['access_token'], isNotNull);
    });
  });

  test('finding 2: a refresh token is not accepted as a Bearer access token',
      () async {
    final refresh = JwtService(testJwtSecret).generateRefreshToken(
      userId: 1,
      username: 'u',
      role: 'admin',
      scopes: ['system/*.*'],
    );
    final r = await handler(testRequest('GET', '/Patient', authToken: refresh));
    expect(r.statusCode, 401);
  });

  test('finding 9: POST /[type]/_search is a search, open to user/*.rs',
      () async {
    final token = generateTestToken(scopes: ['user/*.rs']);
    final r = await handler(
      testRequest(
        'POST',
        '/Patient/_search',
        headers: {'content-type': 'application/x-www-form-urlencoded'},
        body: 'gender=male',
        authToken: token,
      ),
    );
    expect(r.statusCode, 200, reason: await r.readAsString());
  });

  group('findings 3 and 4: compartment routes', () {
    setUp(() async {
      for (final id in ['A', 'B']) {
        await db.saveResource(
          fhir.Patient.fromJson({'resourceType': 'Patient', 'id': id}),
        );
      }
      await db.saveResource(
        fhir.Observation.fromJson({
          'resourceType': 'Observation',
          'id': 'obsB',
          'status': 'final',
          'code': {'text': 'x'},
          'subject': {'reference': 'Patient/B'},
        }),
      );
    });

    test("a patient-scoped token cannot read another patient's compartment",
        () async {
      final token = generateTestToken(scopes: ['patient/*.rs'], patientId: 'A');
      for (final path in [
        '/Patient/B/Observation',
        r'/Patient/B/$everything',
      ]) {
        final r = await handler(testRequest('GET', path, authToken: token));
        expect(r.statusCode, 403, reason: path);
      }
    });

    test('a patient-scoped token still reads its own compartment', () async {
      final token = generateTestToken(scopes: ['patient/*.rs'], patientId: 'B');
      for (final path in [
        '/Patient/B/Observation',
        r'/Patient/B/$everything',
      ]) {
        final r = await handler(testRequest('GET', path, authToken: token));
        expect(r.statusCode, 200, reason: '$path ${await r.readAsString()}');
      }
    });

    test('the compartment search checks the scope on the type it returns',
        () async {
      final token = generateTestToken(scopes: ['user/Patient.rs']);
      final r = await handler(
        testRequest('GET', '/Patient/B/Observation', authToken: token),
      );
      expect(r.statusCode, 403, reason: await r.readAsString());
    });

    test(r'$everything refuses a token that cannot read every type returned',
        () async {
      final token = generateTestToken(scopes: ['user/Patient.rs']);
      final all = await handler(
        testRequest('GET', r'/Patient/B/$everything', authToken: token),
      );
      expect(all.statusCode, 403);
      expect(await all.readAsString(), contains('Observation'));
      // Narrowed to the type it may read, it answers.
      final narrowed = await handler(
        testRequest(
          'GET',
          r'/Patient/B/$everything?_type=Patient',
          authToken: token,
        ),
      );
      expect(narrowed.statusCode, 200, reason: await narrowed.readAsString());
    });
  });

  test(r'finding 5: $meta-add is a write, refused to user/*.rs', () async {
    await db.saveResource(
      fhir.Patient.fromJson({'resourceType': 'Patient', 'id': 'm'}),
    );
    final token = generateTestToken(scopes: ['user/*.rs']);
    final r = await handler(
      testRequest(
        'POST',
        r'/Patient/m/$meta-add',
        body: jsonEncode({
          'resourceType': 'Parameters',
          'parameter': [
            {
              'name': 'meta',
              'valueMeta': {
                'tag': [
                  {'system': 'http://t', 'code': 'x'},
                ],
              },
            },
          ],
        }),
        authToken: token,
      ),
    );
    expect(r.statusCode, 403, reason: await r.readAsString());
  });

  test("finding 6: the patient context is the account's, not the caller's",
      () async {
    final admin = await registerAdmin();
    await register(
      admin,
      'patient1',
      scopes: ['patient/*.rs'],
      patient: 'Patient/pat-linked',
    );
    final login = await handler(
      testRequest(
        'POST',
        '/auth/login',
        body: jsonEncode({
          'username': 'patient1',
          'password': 'patient1pass12345',
          'patient_id': 'someone-else',
        }),
      ),
    );
    expect(login.statusCode, 200);
    final body = await json(login);
    expect(body['patient'], 'pat-linked');
    final payload =
        JwtService(testJwtSecret).verifyToken(body['token'] as String);
    expect(payload!['patient'], 'pat-linked');
  });

  test('finding 7: failed OAuth authorize attempts count toward lockout',
      () async {
    await registerAdmin();
    for (var i = 0; i < 6; i++) {
      await handler(
        testRequest(
          'POST',
          '/auth/authorize',
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'response_type': 'code',
            'client_id': 'app',
            'redirect_uri': 'http://localhost/cb',
            'code_challenge': challenge,
            'code_challenge_method': 'S256',
            'username': 'admin1',
            'password': 'wrong-password-$i',
          }),
        ),
      );
    }
    final login = await handler(
      testRequest(
        'POST',
        '/auth/login',
        body: jsonEncode({'username': 'admin1', 'password': 'admin1pass12345'}),
      ),
    );
    expect(login.statusCode, 423);
  });

  group('finding 11: the rate limiter runs before authentication and audit',
      () {
    test('an unauthenticated flood is throttled and leaves no AuditEvents',
        () async {
      final rawDb = FhirAntDb(NativeDatabase.memory());
      await rawDb.initialize();
      addTearDown(rawDb.close);
      final server = FhirAntServer(
        rawDb,
        jwtSecret: testJwtSecret,
        maxRequests: 5,
      );
      final h = server.createHandler(server.createRouter());
      final statuses = <int>[];
      for (var i = 0; i < 8; i++) {
        statuses.add((await h(testRequest('GET', '/Patient'))).statusCode);
      }
      expect(statuses.where((s) => s == 401), hasLength(5));
      expect(statuses.where((s) => s == 429), hasLength(3));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        await rawDb.getResourceCount(fhir.R4ResourceType.AuditEvent),
        0,
        reason: 'a request presenting no credential writes no audit row',
      );
    });

    test('the credential endpoints have their own, tighter bucket', () async {
      final rawDb = FhirAntDb(NativeDatabase.memory());
      await rawDb.initialize();
      addTearDown(rawDb.close);
      final server = FhirAntServer(
        rawDb,
        jwtSecret: testJwtSecret,
        maxRequests: 100,
        authMaxRequests: 3,
      );
      final h = server.createHandler(server.createRouter());
      final statuses = <int>[];
      for (var i = 0; i < 5; i++) {
        statuses.add(
          (await h(
            testRequest(
              'POST',
              '/auth/login',
              body: jsonEncode({'username': 'nobody', 'password': 'x'}),
            ),
          ))
              .statusCode,
        );
      }
      expect(statuses.where((s) => s == 429), hasLength(2));
      // The data API is untouched by the credential bucket.
      final r = await h(testRequest('GET', '/metadata'));
      expect(r.statusCode, 200);
    });
  });
}
