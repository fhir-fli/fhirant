import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/authorize_handler.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

class MockUser extends Mock implements User {}

/// A syntactically valid S256 challenge; the handlers do not verify it
/// against a verifier (the token endpoint does), only that it is present
/// with method S256.
const pkceQuery = '&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM'
    '&code_challenge_method=S256';
const pkceFields = {
  'code_challenge': 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
  'code_challenge_method': 'S256',
};

/// A user with valid credentials and nothing standing in the way.
MockUser activeUser(
  String username,
  String password, {
  String role = 'clinician',
}) {
  final salt = PasswordHasher.generateSalt();
  final hash = PasswordHasher.hashPassword(password, salt);
  final mockUser = MockUser();
  when(() => mockUser.id).thenReturn(1);
  when(() => mockUser.username).thenReturn(username);
  when(() => mockUser.salt).thenReturn(salt);
  when(() => mockUser.passwordHash).thenReturn(hash);
  when(() => mockUser.active).thenReturn(true);
  when(() => mockUser.role).thenReturn(role);
  when(() => mockUser.scopes).thenReturn(null);
  when(() => mockUser.failedLoginCount).thenReturn(0);
  when(() => mockUser.lockedUntil).thenReturn(null);
  when(() => mockUser.patientId).thenReturn(null);
  return mockUser;
}

/// The stubs every successful authorize needs from the store.
void stubIssue(MockFhirAntDb mockDb) {
  when(() => mockDb.getOAuthClientRedirect(any()))
      .thenAnswer((_) async => null);
  when(() => mockDb.registerOAuthClient(any(), any())).thenAnswer((_) async {});
  when(() => mockDb.updateLastLogin(any())).thenAnswer((_) async {});
  when(
    () => mockDb.createAuthorizationCode(
      code: any(named: 'code'),
      clientId: any(named: 'clientId'),
      userId: any(named: 'userId'),
      redirectUri: any(named: 'redirectUri'),
      scope: any(named: 'scope'),
      codeChallenge: any(named: 'codeChallenge'),
      codeChallengeMethod: any(named: 'codeChallengeMethod'),
      expiresAt: any(named: 'expiresAt'),
    ),
  ).thenAnswer((_) async {});
}

void main() {
  group('authorizeGetHandler', () {
    late MockFhirAntDb mockDb;

    setUp(() {
      mockDb = MockFhirAntDb();
      when(() => mockDb.getOAuthClientRedirect(any()))
          .thenAnswer((_) async => null);
    });

    test('returns 400 when client_id missing', () async {
      final request = Request(
        'GET',
        Uri.parse(
          'http://localhost:8080/auth/authorize?response_type=code&redirect_uri=http://app/cb',
        ),
      );

      final response = await authorizeGetHandler(request, mockDb);
      expect(response.statusCode, 400);
      expect(response.headers['content-type'], contains('text/html'));
    });

    test('returns 400 when redirect_uri missing', () async {
      final request = Request(
        'GET',
        Uri.parse(
          'http://localhost:8080/auth/authorize?response_type=code&client_id=my-app',
        ),
      );

      final response = await authorizeGetHandler(request, mockDb);
      expect(response.statusCode, 400);
    });

    test(
        'redirects a registered client with error for unsupported '
        'response_type', () async {
      when(() => mockDb.getOAuthClientRedirect('my-app'))
          .thenAnswer((_) async => 'http://app/cb');
      final request = Request(
        'GET',
        Uri.parse(
          'http://localhost:8080/auth/authorize?response_type=token&client_id=my-app&redirect_uri=http://app/cb',
        ),
      );

      final response = await authorizeGetHandler(request, mockDb);
      expect(response.statusCode, 302);
      final location = response.headers['location']!;
      expect(location, contains('error=unsupported_response_type'));
    });

    test(
        "an unregistered client's error is shown, never redirected "
        '(RFC 6749 4.1.2.1)', () async {
      // REVIEW-2026-09-08 row 15: this used to 302 to any redirect_uri a
      // new client_id named, an open redirect.
      when(() => mockDb.getOAuthClientRedirect('new-app'))
          .thenAnswer((_) async => null);
      final request = Request(
        'GET',
        Uri.parse(
          'http://localhost:8080/auth/authorize?response_type=token&client_id=new-app&redirect_uri=https://evil.example/cb&state=x',
        ),
      );

      final response = await authorizeGetHandler(request, mockDb);
      expect(response.statusCode, 400);
      expect(response.headers['location'], isNull);
    });

    test(
        'redirects a registered client with invalid_request when PKCE is '
        'missing', () async {
      when(() => mockDb.getOAuthClientRedirect('my-app'))
          .thenAnswer((_) async => 'http://app/cb');
      final request = Request(
        'GET',
        Uri.parse(
          'http://localhost:8080/auth/authorize?response_type=code&client_id=my-app&redirect_uri=http://app/cb&scope=user/*.*&state=xyz',
        ),
      );

      final response = await authorizeGetHandler(request, mockDb);
      expect(response.statusCode, 302);
      final location = response.headers['location']!;
      expect(location, contains('error=invalid_request'));
      expect(location, contains('code_challenge'));
    });

    test(
        'refuses, without redirecting, a redirect_uri other than the pinned '
        'one', () async {
      when(() => mockDb.getOAuthClientRedirect('my-app'))
          .thenAnswer((_) async => 'http://app/cb');
      final request = Request(
        'GET',
        Uri.parse(
          'http://localhost:8080/auth/authorize?response_type=code&client_id=my-app&redirect_uri=http://evil/cb&scope=user/*.*$pkceQuery',
        ),
      );

      final response = await authorizeGetHandler(request, mockDb);
      expect(response.statusCode, 400);
      expect(response.headers['location'], isNull);
    });

    test('returns HTML login form for valid params', () async {
      final request = Request(
        'GET',
        Uri.parse(
          'http://localhost:8080/auth/authorize?response_type=code&client_id=my-app&redirect_uri=http://app/cb&scope=user/*.*&state=xyz$pkceQuery',
        ),
      );

      final response = await authorizeGetHandler(request, mockDb);
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('text/html'));

      final body = await response.readAsString();
      expect(body, contains('FHIRant'));
      expect(body, contains('my-app'));
      expect(body, contains('user/*.*'));
    });
  });

  group('authorizeJsonHandler', () {
    late MockFhirAntDb mockDb;

    setUp(() {
      mockDb = MockFhirAntDb();
      stubIssue(mockDb);
    });

    Request makeRequest(Map<String, dynamic> body) {
      return Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/authorize'),
        body: jsonEncode(body),
        headers: {'content-type': 'application/json'},
      );
    }

    test('returns 400 for unsupported response_type', () async {
      final request = makeRequest({
        'response_type': 'token',
        'client_id': 'my-app',
        'redirect_uri': 'http://app/cb',
        'username': 'test',
        'password': 'pass',
      });

      final response = await authorizeJsonHandler(request, mockDb);
      expect(response.statusCode, 400);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'unsupported_response_type');
    });

    test('returns 400 when client_id missing', () async {
      final request = makeRequest({
        'response_type': 'code',
        'redirect_uri': 'http://app/cb',
        'username': 'test',
        'password': 'pass',
      });

      final response = await authorizeJsonHandler(request, mockDb);
      expect(response.statusCode, 400);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'invalid_request');
    });

    test('returns 400 when redirect_uri missing', () async {
      final request = makeRequest({
        'response_type': 'code',
        'client_id': 'my-app',
        'username': 'test',
        'password': 'pass',
      });

      final response = await authorizeJsonHandler(request, mockDb);
      expect(response.statusCode, 400);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'invalid_request');
    });

    test('returns 400 when credentials missing', () async {
      final request = makeRequest({
        'response_type': 'code',
        'client_id': 'my-app',
        'redirect_uri': 'http://app/cb',
      });

      final response = await authorizeJsonHandler(request, mockDb);
      expect(response.statusCode, 400);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'invalid_request');
    });

    test('returns 400 invalid_request without PKCE', () async {
      final request = makeRequest({
        'response_type': 'code',
        'client_id': 'my-app',
        'redirect_uri': 'http://app/cb',
        'username': 'testuser',
        'password': 'validpass',
      });

      final response = await authorizeJsonHandler(request, mockDb);
      expect(response.statusCode, 400);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'invalid_request');
    });

    test('returns 400 invalid_request for the plain method', () async {
      final request = makeRequest({
        'response_type': 'code',
        'client_id': 'my-app',
        'redirect_uri': 'http://app/cb',
        'code_challenge': 'abc',
        'code_challenge_method': 'plain',
        'username': 'testuser',
        'password': 'validpass',
      });

      final response = await authorizeJsonHandler(request, mockDb);
      expect(response.statusCode, 400);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'invalid_request');
    });

    test('returns 401 for invalid credentials', () async {
      when(() => mockDb.getUserByUsername('baduser'))
          .thenAnswer((_) async => null);

      final request = makeRequest({
        'response_type': 'code',
        'client_id': 'my-app',
        'redirect_uri': 'http://app/cb',
        ...pkceFields,
        'username': 'baduser',
        'password': 'badpass',
      });

      final response = await authorizeJsonHandler(request, mockDb);
      expect(response.statusCode, 401);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'access_denied');
    });

    test('returns 403 for deactivated user', () async {
      final mockUser = activeUser('inactive', 'validpass');
      when(() => mockUser.active).thenReturn(false);

      when(() => mockDb.getUserByUsername('inactive'))
          .thenAnswer((_) async => mockUser);

      final request = makeRequest({
        'response_type': 'code',
        'client_id': 'my-app',
        'redirect_uri': 'http://app/cb',
        ...pkceFields,
        'username': 'inactive',
        'password': 'validpass',
      });

      final response = await authorizeJsonHandler(request, mockDb);
      expect(response.statusCode, 403);
    });

    test('returns authorization code for valid request', () async {
      final mockUser = activeUser('testuser', 'validpass');
      when(() => mockDb.getUserByUsername('testuser'))
          .thenAnswer((_) async => mockUser);

      final request = makeRequest({
        'response_type': 'code',
        'client_id': 'my-app',
        'redirect_uri': 'http://app/cb',
        'scope': 'user/*.*',
        'state': 'csrf-token',
        ...pkceFields,
        'username': 'testuser',
        'password': 'validpass',
      });

      final response = await authorizeJsonHandler(request, mockDb);
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['code'], isA<String>());
      expect(body['code'], isNotEmpty);
      expect(body['state'], 'csrf-token');
      expect(body['redirect_uri'], contains('code='));
      expect(body['redirect_uri'], contains('state=csrf-token'));

      // Verify the auth code was stored, with the redirect pinned.
      verify(
        () => mockDb.createAuthorizationCode(
          code: any(named: 'code'),
          clientId: 'my-app',
          userId: 1,
          redirectUri: 'http://app/cb',
          scope: 'user/*.*',
          codeChallenge: pkceFields['code_challenge'],
          codeChallengeMethod: 'S256',
          expiresAt: any(named: 'expiresAt'),
        ),
      ).called(1);
      verify(() => mockDb.registerOAuthClient('my-app', 'http://app/cb'))
          .called(1);
    });

    test('the scope stored is the request intersected with the account',
        () async {
      final mockUser = activeUser('ro', 'validpass', role: 'readonly');
      when(() => mockDb.getUserByUsername('ro'))
          .thenAnswer((_) async => mockUser);

      final request = makeRequest({
        'response_type': 'code',
        'client_id': 'my-app',
        'redirect_uri': 'http://app/cb',
        'scope': 'user/*.cruds openid',
        ...pkceFields,
        'username': 'ro',
        'password': 'validpass',
      });

      final response = await authorizeJsonHandler(request, mockDb);
      expect(response.statusCode, 200);
      verify(
        () => mockDb.createAuthorizationCode(
          code: any(named: 'code'),
          clientId: 'my-app',
          userId: 1,
          redirectUri: 'http://app/cb',
          scope: 'user/*.rs openid',
          codeChallenge: any(named: 'codeChallenge'),
          codeChallengeMethod: any(named: 'codeChallengeMethod'),
          expiresAt: any(named: 'expiresAt'),
        ),
      ).called(1);
    });

    test('a request wholly outside the grant is invalid_scope', () async {
      final mockUser = activeUser('ro', 'validpass', role: 'readonly');
      when(() => mockDb.getUserByUsername('ro'))
          .thenAnswer((_) async => mockUser);

      final request = makeRequest({
        'response_type': 'code',
        'client_id': 'my-app',
        'redirect_uri': 'http://app/cb',
        'scope': 'system/*.*',
        ...pkceFields,
        'username': 'ro',
        'password': 'validpass',
      });

      final response = await authorizeJsonHandler(request, mockDb);
      expect(response.statusCode, 400);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'invalid_scope');
    });

    test('stores PKCE challenge', () async {
      final mockUser = activeUser('testuser', 'validpass');
      when(() => mockDb.getUserByUsername('testuser'))
          .thenAnswer((_) async => mockUser);

      final request = makeRequest({
        'response_type': 'code',
        'client_id': 'my-app',
        'redirect_uri': 'http://app/cb',
        'scope': 'user/*.*',
        'username': 'testuser',
        'password': 'validpass',
        'code_challenge': 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
        'code_challenge_method': 'S256',
      });

      final response = await authorizeJsonHandler(request, mockDb);
      expect(response.statusCode, 200);

      // Verify PKCE challenge was stored
      verify(
        () => mockDb.createAuthorizationCode(
          code: any(named: 'code'),
          clientId: 'my-app',
          userId: 1,
          redirectUri: 'http://app/cb',
          scope: 'user/*.*',
          codeChallenge: 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
          codeChallengeMethod: 'S256',
          expiresAt: any(named: 'expiresAt'),
        ),
      ).called(1);
    });
  });

  group('authorizePostHandler (form-encoded)', () {
    late MockFhirAntDb mockDb;

    setUp(() {
      mockDb = MockFhirAntDb();
      stubIssue(mockDb);
    });

    Request makeFormRequest(Map<String, String> fields) {
      final body = fields.entries
          .map(
            (e) =>
                '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
          )
          .join('&');
      return Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/authorize'),
        body: body,
        headers: {'content-type': 'application/x-www-form-urlencoded'},
      );
    }

    test('returns 302 redirect with code for valid form submission', () async {
      final mockUser = activeUser('testuser', 'validpass');
      when(() => mockDb.getUserByUsername('testuser'))
          .thenAnswer((_) async => mockUser);

      final request = makeFormRequest({
        'response_type': 'code',
        'client_id': 'my-app',
        'redirect_uri': 'http://app/cb',
        'scope': 'user/*.*',
        'state': 'csrf-token',
        ...pkceFields,
        'username': 'testuser',
        'password': 'validpass',
      });

      final response = await authorizePostHandler(request, mockDb);
      expect(response.statusCode, 302);

      final location = response.headers['location']!;
      expect(location, startsWith('http://app/cb'));
      expect(location, contains('code='));
      expect(location, contains('state=csrf-token'));
    });

    test('returns login form with error for bad credentials', () async {
      when(() => mockDb.getUserByUsername('baduser'))
          .thenAnswer((_) async => null);

      final request = makeFormRequest({
        'response_type': 'code',
        'client_id': 'my-app',
        'redirect_uri': 'http://app/cb',
        ...pkceFields,
        'username': 'baduser',
        'password': 'badpass',
      });

      final response = await authorizePostHandler(request, mockDb);
      expect(response.statusCode, 200); // re-renders form
      expect(response.headers['content-type'], contains('text/html'));

      final body = await response.readAsString();
      expect(body, contains('Invalid username or password'));
    });

    test('returns login form when credentials missing', () async {
      final request = makeFormRequest({
        'response_type': 'code',
        'client_id': 'my-app',
        'redirect_uri': 'http://app/cb',
      });

      final response = await authorizePostHandler(request, mockDb);
      expect(response.statusCode, 200); // re-renders form
      final body = await response.readAsString();
      expect(body, contains('Username and password are required'));
    });
  });

  test('a locked account is told so on the form, and failures count', () async {
    final mockDb = MockFhirAntDb();
    stubIssue(mockDb);
    final mockUser = activeUser('testuser', 'validpass');
    when(() => mockUser.failedLoginCount).thenReturn(4);
    when(() => mockDb.getUserByUsername('testuser'))
        .thenAnswer((_) async => mockUser);
    when(() => mockDb.incrementFailedLogins(1)).thenAnswer((_) async => 5);
    when(() => mockDb.lockAccount(1, any())).thenAnswer((_) async {});

    final body = {
      'response_type': 'code',
      'client_id': 'my-app',
      'redirect_uri': 'http://app/cb',
      ...pkceFields,
      'username': 'testuser',
      'password': 'wrong',
    };
    final response = await authorizeJsonHandler(
      Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/authorize'),
        body: jsonEncode(body),
        headers: {'content-type': 'application/json'},
      ),
      mockDb,
    );
    expect(response.statusCode, 423);
    verify(() => mockDb.incrementFailedLogins(1)).called(1);
    verify(() => mockDb.lockAccount(1, any())).called(1);
  });
}
