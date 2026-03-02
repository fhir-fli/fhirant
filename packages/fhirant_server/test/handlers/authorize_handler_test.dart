import 'dart:convert';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/authorize_handler.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';
import 'package:shelf/shelf.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

class MockUser extends Mock implements User {}

void main() {
  group('authorizeGetHandler', () {
    test('returns 400 when client_id missing', () async {
      final request = Request(
        'GET',
        Uri.parse(
            'http://localhost:8080/auth/authorize?response_type=code&redirect_uri=http://app/cb'),
      );

      final response = await authorizeGetHandler(request);
      expect(response.statusCode, 400);
      expect(response.headers['content-type'], contains('text/html'));
    });

    test('returns 400 when redirect_uri missing', () async {
      final request = Request(
        'GET',
        Uri.parse(
            'http://localhost:8080/auth/authorize?response_type=code&client_id=my-app'),
      );

      final response = await authorizeGetHandler(request);
      expect(response.statusCode, 400);
    });

    test('redirects with error for unsupported response_type', () async {
      final request = Request(
        'GET',
        Uri.parse(
            'http://localhost:8080/auth/authorize?response_type=token&client_id=my-app&redirect_uri=http://app/cb'),
      );

      final response = await authorizeGetHandler(request);
      expect(response.statusCode, 302);
      final location = response.headers['location']!;
      expect(location, contains('error=unsupported_response_type'));
    });

    test('returns HTML login form for valid params', () async {
      final request = Request(
        'GET',
        Uri.parse(
            'http://localhost:8080/auth/authorize?response_type=code&client_id=my-app&redirect_uri=http://app/cb&scope=user/*.*&state=xyz'),
      );

      final response = await authorizeGetHandler(request);
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
    });

    Request _makeRequest(Map<String, dynamic> body) {
      return Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/authorize'),
        body: jsonEncode(body),
        headers: {'content-type': 'application/json'},
      );
    }

    test('returns 400 for unsupported response_type', () async {
      final request = _makeRequest({
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
      final request = _makeRequest({
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
      final request = _makeRequest({
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
      final request = _makeRequest({
        'response_type': 'code',
        'client_id': 'my-app',
        'redirect_uri': 'http://app/cb',
      });

      final response = await authorizeJsonHandler(request, mockDb);
      expect(response.statusCode, 400);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'invalid_request');
    });

    test('returns 401 for invalid credentials', () async {
      when(() => mockDb.getUserByUsername('baduser'))
          .thenAnswer((_) async => null);

      final request = _makeRequest({
        'response_type': 'code',
        'client_id': 'my-app',
        'redirect_uri': 'http://app/cb',
        'username': 'baduser',
        'password': 'badpass',
      });

      final response = await authorizeJsonHandler(request, mockDb);
      expect(response.statusCode, 401);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'access_denied');
    });

    test('returns 403 for deactivated user', () async {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hashPassword('validpass', salt);

      final mockUser = MockUser();
      when(() => mockUser.id).thenReturn(1);
      when(() => mockUser.username).thenReturn('inactive');
      when(() => mockUser.salt).thenReturn(salt);
      when(() => mockUser.passwordHash).thenReturn(hash);
      when(() => mockUser.active).thenReturn(false);

      when(() => mockDb.getUserByUsername('inactive'))
          .thenAnswer((_) async => mockUser);

      final request = _makeRequest({
        'response_type': 'code',
        'client_id': 'my-app',
        'redirect_uri': 'http://app/cb',
        'username': 'inactive',
        'password': 'validpass',
      });

      final response = await authorizeJsonHandler(request, mockDb);
      expect(response.statusCode, 403);
    });

    test('returns authorization code for valid request', () async {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hashPassword('validpass', salt);

      final mockUser = MockUser();
      when(() => mockUser.id).thenReturn(1);
      when(() => mockUser.username).thenReturn('testuser');
      when(() => mockUser.salt).thenReturn(salt);
      when(() => mockUser.passwordHash).thenReturn(hash);
      when(() => mockUser.active).thenReturn(true);

      when(() => mockDb.getUserByUsername('testuser'))
          .thenAnswer((_) async => mockUser);
      when(() => mockDb.createAuthorizationCode(
            code: any(named: 'code'),
            clientId: any(named: 'clientId'),
            userId: any(named: 'userId'),
            redirectUri: any(named: 'redirectUri'),
            scope: any(named: 'scope'),
            codeChallenge: any(named: 'codeChallenge'),
            codeChallengeMethod: any(named: 'codeChallengeMethod'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async {});

      final request = _makeRequest({
        'response_type': 'code',
        'client_id': 'my-app',
        'redirect_uri': 'http://app/cb',
        'scope': 'user/*.*',
        'state': 'csrf-token',
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

      // Verify the auth code was stored
      verify(() => mockDb.createAuthorizationCode(
            code: any(named: 'code'),
            clientId: 'my-app',
            userId: 1,
            redirectUri: 'http://app/cb',
            scope: 'user/*.*',
            codeChallenge: null,
            codeChallengeMethod: null,
            expiresAt: any(named: 'expiresAt'),
          )).called(1);
    });

    test('stores PKCE challenge when provided', () async {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hashPassword('validpass', salt);

      final mockUser = MockUser();
      when(() => mockUser.id).thenReturn(1);
      when(() => mockUser.username).thenReturn('testuser');
      when(() => mockUser.salt).thenReturn(salt);
      when(() => mockUser.passwordHash).thenReturn(hash);
      when(() => mockUser.active).thenReturn(true);

      when(() => mockDb.getUserByUsername('testuser'))
          .thenAnswer((_) async => mockUser);
      when(() => mockDb.createAuthorizationCode(
            code: any(named: 'code'),
            clientId: any(named: 'clientId'),
            userId: any(named: 'userId'),
            redirectUri: any(named: 'redirectUri'),
            scope: any(named: 'scope'),
            codeChallenge: any(named: 'codeChallenge'),
            codeChallengeMethod: any(named: 'codeChallengeMethod'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async {});

      final request = _makeRequest({
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
      verify(() => mockDb.createAuthorizationCode(
            code: any(named: 'code'),
            clientId: 'my-app',
            userId: 1,
            redirectUri: 'http://app/cb',
            scope: 'user/*.*',
            codeChallenge: 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
            codeChallengeMethod: 'S256',
            expiresAt: any(named: 'expiresAt'),
          )).called(1);
    });
  });

  group('authorizePostHandler (form-encoded)', () {
    late MockFhirAntDb mockDb;

    setUp(() {
      mockDb = MockFhirAntDb();
    });

    Request _makeFormRequest(Map<String, String> fields) {
      final body = fields.entries
          .map((e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');
      return Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/authorize'),
        body: body,
        headers: {'content-type': 'application/x-www-form-urlencoded'},
      );
    }

    test('returns 302 redirect with code for valid form submission', () async {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hashPassword('validpass', salt);

      final mockUser = MockUser();
      when(() => mockUser.id).thenReturn(1);
      when(() => mockUser.username).thenReturn('testuser');
      when(() => mockUser.salt).thenReturn(salt);
      when(() => mockUser.passwordHash).thenReturn(hash);
      when(() => mockUser.active).thenReturn(true);

      when(() => mockDb.getUserByUsername('testuser'))
          .thenAnswer((_) async => mockUser);
      when(() => mockDb.createAuthorizationCode(
            code: any(named: 'code'),
            clientId: any(named: 'clientId'),
            userId: any(named: 'userId'),
            redirectUri: any(named: 'redirectUri'),
            scope: any(named: 'scope'),
            codeChallenge: any(named: 'codeChallenge'),
            codeChallengeMethod: any(named: 'codeChallengeMethod'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async {});

      final request = _makeFormRequest({
        'response_type': 'code',
        'client_id': 'my-app',
        'redirect_uri': 'http://app/cb',
        'scope': 'user/*.*',
        'state': 'csrf-token',
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

      final request = _makeFormRequest({
        'response_type': 'code',
        'client_id': 'my-app',
        'redirect_uri': 'http://app/cb',
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
      final request = _makeFormRequest({
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
}
