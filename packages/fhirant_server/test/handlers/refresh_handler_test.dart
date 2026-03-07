import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/refresh_handler.dart';
import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:fhirant_server/src/utils/token_hasher.dart';
import 'package:shelf/shelf.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

class MockUser extends Mock implements User {}

class MockAuthorizationCode extends Mock implements AuthorizationCode {}

void main() {
  group('refreshHandler — refresh_token grant', () {
    late MockFhirAntDb mockDb;
    late JwtService jwtService;

    setUp(() {
      mockDb = MockFhirAntDb();
      jwtService = JwtService('test-secret');
      // Default stubs for token revocation
      when(() => mockDb.isTokenRevoked(any())).thenAnswer((_) async => false);
      when(() => mockDb.revokeToken(any(), any())).thenAnswer((_) async {});
    });

    Request _makeRequest(Map<String, dynamic> body) {
      return Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/token'),
        body: jsonEncode(body),
      );
    }

    test('returns 400 for unsupported grant_type', () async {
      final request =
          _makeRequest({'grant_type': 'client_credentials'});

      final response = await refreshHandler(request, mockDb, jwtService);
      expect(response.statusCode, 400);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'unsupported_grant_type');
    });

    test('returns 400 when refresh_token is missing', () async {
      final request = _makeRequest({'grant_type': 'refresh_token'});

      final response = await refreshHandler(request, mockDb, jwtService);
      expect(response.statusCode, 400);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'invalid_request');
    });

    test('returns 401 for invalid refresh token', () async {
      final request = _makeRequest({
        'grant_type': 'refresh_token',
        'refresh_token': 'invalid-token',
      });

      final response = await refreshHandler(request, mockDb, jwtService);
      expect(response.statusCode, 401);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'invalid_grant');
    });

    test('returns 401 when using access token as refresh token', () async {
      final accessToken = jwtService.generateToken(
        userId: 1,
        username: 'testuser',
        role: 'admin',
      );

      final request = _makeRequest({
        'grant_type': 'refresh_token',
        'refresh_token': accessToken,
      });

      final response = await refreshHandler(request, mockDb, jwtService);
      expect(response.statusCode, 401);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'invalid_grant');
    });

    test('returns new tokens for valid refresh token', () async {
      final refreshToken = jwtService.generateRefreshToken(
        userId: 1,
        username: 'testuser',
        role: 'admin',
        scopes: ['system/*.*'],
      );

      final mockUser = MockUser();
      when(() => mockUser.id).thenReturn(1);
      when(() => mockUser.username).thenReturn('testuser');
      when(() => mockUser.role).thenReturn('admin');
      when(() => mockUser.active).thenReturn(true);
      when(() => mockUser.scopes).thenReturn(null);

      when(() => mockDb.getUserByUsername('testuser'))
          .thenAnswer((_) async => mockUser);

      final request = _makeRequest({
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      });

      final response = await refreshHandler(request, mockDb, jwtService);
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['access_token'], isNotNull);
      expect(body['refresh_token'], isNotNull);
      expect(body['token_type'], 'Bearer');
      expect(body['username'], 'testuser');
      expect(body['role'], 'admin');

      // Verify the new access token is valid
      final newPayload =
          jwtService.verifyToken(body['access_token'] as String);
      expect(newPayload, isNotNull);
      expect(newPayload!['username'], 'testuser');

      // Verify the new refresh token is valid
      final newRefreshPayload =
          jwtService.verifyRefreshToken(body['refresh_token'] as String);
      expect(newRefreshPayload, isNotNull);
    });

    test('returns 401 when user no longer exists', () async {
      final refreshToken = jwtService.generateRefreshToken(
        userId: 1,
        username: 'deleted-user',
        role: 'admin',
      );

      when(() => mockDb.getUserByUsername('deleted-user'))
          .thenAnswer((_) async => null);

      final request = _makeRequest({
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      });

      final response = await refreshHandler(request, mockDb, jwtService);
      expect(response.statusCode, 401);
    });

    test('returns 403 when user account is deactivated', () async {
      final refreshToken = jwtService.generateRefreshToken(
        userId: 1,
        username: 'inactive',
        role: 'admin',
      );

      final mockUser = MockUser();
      when(() => mockUser.id).thenReturn(1);
      when(() => mockUser.username).thenReturn('inactive');
      when(() => mockUser.role).thenReturn('admin');
      when(() => mockUser.active).thenReturn(false);

      when(() => mockDb.getUserByUsername('inactive'))
          .thenAnswer((_) async => mockUser);

      final request = _makeRequest({
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      });

      final response = await refreshHandler(request, mockDb, jwtService);
      expect(response.statusCode, 403);
    });

    test('preserves patient context through refresh', () async {
      final refreshToken = jwtService.generateRefreshToken(
        userId: 1,
        username: 'patientuser',
        role: 'readonly',
        scopes: ['patient/Patient.r', 'patient/Observation.r'],
        patientId: 'pat-123',
      );

      final mockUser = MockUser();
      when(() => mockUser.id).thenReturn(1);
      when(() => mockUser.username).thenReturn('patientuser');
      when(() => mockUser.role).thenReturn('readonly');
      when(() => mockUser.active).thenReturn(true);
      when(() => mockUser.scopes).thenReturn(null);

      when(() => mockDb.getUserByUsername('patientuser'))
          .thenAnswer((_) async => mockUser);

      final request = _makeRequest({
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      });

      final response = await refreshHandler(request, mockDb, jwtService);
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['patient'], 'pat-123');

      // Verify the new access token has patient claim
      final newPayload =
          jwtService.verifyToken(body['access_token'] as String);
      expect(newPayload!['patient'], 'pat-123');
    });

    test('supports form-encoded body', () async {
      final refreshToken = jwtService.generateRefreshToken(
        userId: 1,
        username: 'testuser',
        role: 'admin',
        scopes: ['system/*.*'],
      );

      final mockUser = MockUser();
      when(() => mockUser.id).thenReturn(1);
      when(() => mockUser.username).thenReturn('testuser');
      when(() => mockUser.role).thenReturn('admin');
      when(() => mockUser.active).thenReturn(true);
      when(() => mockUser.scopes).thenReturn(null);

      when(() => mockDb.getUserByUsername('testuser'))
          .thenAnswer((_) async => mockUser);

      final formBody =
          'grant_type=refresh_token&refresh_token=${Uri.encodeComponent(refreshToken)}';
      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/token'),
        body: formBody,
      );

      final response = await refreshHandler(request, mockDb, jwtService);
      expect(response.statusCode, 200);
    });

    test('old refresh token is revoked after rotation', () async {
      final refreshToken = jwtService.generateRefreshToken(
        userId: 1,
        username: 'testuser',
        role: 'admin',
        scopes: ['system/*.*'],
      );

      final mockUser = MockUser();
      when(() => mockUser.id).thenReturn(1);
      when(() => mockUser.username).thenReturn('testuser');
      when(() => mockUser.role).thenReturn('admin');
      when(() => mockUser.active).thenReturn(true);
      when(() => mockUser.scopes).thenReturn(null);

      when(() => mockDb.getUserByUsername('testuser'))
          .thenAnswer((_) async => mockUser);

      final request = _makeRequest({
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      });

      final response = await refreshHandler(request, mockDb, jwtService);
      expect(response.statusCode, 200);

      // Verify the old refresh token hash was passed to revokeToken
      final expectedHash = TokenHasher.hash(refreshToken);
      verify(() => mockDb.revokeToken(expectedHash, any())).called(1);
    });

    test('revoked refresh token is rejected', () async {
      final refreshToken = jwtService.generateRefreshToken(
        userId: 1,
        username: 'testuser',
        role: 'admin',
      );

      final refreshHash = TokenHasher.hash(refreshToken);
      when(() => mockDb.isTokenRevoked(refreshHash))
          .thenAnswer((_) async => true);

      final request = _makeRequest({
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      });

      final response = await refreshHandler(request, mockDb, jwtService);
      expect(response.statusCode, 401);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'invalid_grant');
      expect(body['error_description'], contains('revoked'));
    });
  });

  group('refreshHandler — authorization_code grant', () {
    late MockFhirAntDb mockDb;
    late JwtService jwtService;

    setUp(() {
      mockDb = MockFhirAntDb();
      jwtService = JwtService('test-secret');
    });

    Request _makeRequest(Map<String, dynamic> body) {
      return Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/token'),
        body: jsonEncode(body),
      );
    }

    test('returns 400 when code is missing', () async {
      final request = _makeRequest({
        'grant_type': 'authorization_code',
        'redirect_uri': 'http://app.example.com/callback',
      });

      final response = await refreshHandler(request, mockDb, jwtService);
      expect(response.statusCode, 400);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'invalid_request');
    });

    test('returns 400 when redirect_uri is missing', () async {
      final request = _makeRequest({
        'grant_type': 'authorization_code',
        'code': 'some-code',
      });

      final response = await refreshHandler(request, mockDb, jwtService);
      expect(response.statusCode, 400);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'invalid_request');
    });

    test('returns 400 when code not found', () async {
      when(() => mockDb.getAuthorizationCode('bad-code'))
          .thenAnswer((_) async => null);

      final request = _makeRequest({
        'grant_type': 'authorization_code',
        'code': 'bad-code',
        'redirect_uri': 'http://app.example.com/callback',
      });

      final response = await refreshHandler(request, mockDb, jwtService);
      expect(response.statusCode, 400);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'invalid_grant');
      expect(body['error_description'], contains('not found'));
    });

    test('returns 400 when code already used', () async {
      final mockCode = MockAuthorizationCode();
      when(() => mockCode.used).thenReturn(true);

      when(() => mockDb.getAuthorizationCode('used-code'))
          .thenAnswer((_) async => mockCode);

      final request = _makeRequest({
        'grant_type': 'authorization_code',
        'code': 'used-code',
        'redirect_uri': 'http://app.example.com/callback',
      });

      final response = await refreshHandler(request, mockDb, jwtService);
      expect(response.statusCode, 400);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error_description'], contains('already been used'));
    });

    test('returns 400 when code expired', () async {
      final mockCode = MockAuthorizationCode();
      when(() => mockCode.used).thenReturn(false);
      when(() => mockCode.expiresAt)
          .thenReturn(DateTime.now().subtract(const Duration(minutes: 1)));
      when(() => mockCode.code).thenReturn('expired-code');

      when(() => mockDb.getAuthorizationCode('expired-code'))
          .thenAnswer((_) async => mockCode);
      when(() => mockDb.markAuthorizationCodeUsed('expired-code'))
          .thenAnswer((_) async {});

      final request = _makeRequest({
        'grant_type': 'authorization_code',
        'code': 'expired-code',
        'redirect_uri': 'http://app.example.com/callback',
      });

      final response = await refreshHandler(request, mockDb, jwtService);
      expect(response.statusCode, 400);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error_description'], contains('expired'));
    });

    test('returns 400 when redirect_uri does not match', () async {
      final mockCode = MockAuthorizationCode();
      when(() => mockCode.used).thenReturn(false);
      when(() => mockCode.expiresAt)
          .thenReturn(DateTime.now().add(const Duration(minutes: 5)));
      when(() => mockCode.redirectUri)
          .thenReturn('http://app.example.com/callback');

      when(() => mockDb.getAuthorizationCode('valid-code'))
          .thenAnswer((_) async => mockCode);

      final request = _makeRequest({
        'grant_type': 'authorization_code',
        'code': 'valid-code',
        'redirect_uri': 'http://wrong.example.com/callback',
      });

      final response = await refreshHandler(request, mockDb, jwtService);
      expect(response.statusCode, 400);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error_description'], contains('redirect_uri'));
    });

    test('returns 400 when PKCE verifier missing but challenge was stored',
        () async {
      final mockCode = MockAuthorizationCode();
      when(() => mockCode.used).thenReturn(false);
      when(() => mockCode.expiresAt)
          .thenReturn(DateTime.now().add(const Duration(minutes: 5)));
      when(() => mockCode.redirectUri)
          .thenReturn('http://app.example.com/callback');
      when(() => mockCode.clientId).thenReturn('my-app');
      when(() => mockCode.codeChallenge).thenReturn('some-challenge');
      when(() => mockCode.codeChallengeMethod).thenReturn('S256');

      when(() => mockDb.getAuthorizationCode('pkce-code'))
          .thenAnswer((_) async => mockCode);

      final request = _makeRequest({
        'grant_type': 'authorization_code',
        'code': 'pkce-code',
        'redirect_uri': 'http://app.example.com/callback',
        'client_id': 'my-app',
      });

      final response = await refreshHandler(request, mockDb, jwtService);
      expect(response.statusCode, 400);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error_description'], contains('code_verifier'));
    });

    test('returns 400 when PKCE verifier does not match', () async {
      // Generate a proper PKCE pair
      final codeVerifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      // Wrong challenge (doesn't match the verifier)
      final codeChallenge = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

      final mockCode = MockAuthorizationCode();
      when(() => mockCode.used).thenReturn(false);
      when(() => mockCode.expiresAt)
          .thenReturn(DateTime.now().add(const Duration(minutes: 5)));
      when(() => mockCode.redirectUri)
          .thenReturn('http://app.example.com/callback');
      when(() => mockCode.clientId).thenReturn('my-app');
      when(() => mockCode.codeChallenge).thenReturn(codeChallenge);
      when(() => mockCode.codeChallengeMethod).thenReturn('S256');

      when(() => mockDb.getAuthorizationCode('pkce-code'))
          .thenAnswer((_) async => mockCode);

      final request = _makeRequest({
        'grant_type': 'authorization_code',
        'code': 'pkce-code',
        'redirect_uri': 'http://app.example.com/callback',
        'client_id': 'my-app',
        'code_verifier': codeVerifier,
      });

      final response = await refreshHandler(request, mockDb, jwtService);
      expect(response.statusCode, 400);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error_description'], contains('code_verifier'));
    });

    test('exchanges valid code for tokens', () async {
      final mockCode = MockAuthorizationCode();
      when(() => mockCode.code).thenReturn('valid-code');
      when(() => mockCode.used).thenReturn(false);
      when(() => mockCode.expiresAt)
          .thenReturn(DateTime.now().add(const Duration(minutes: 5)));
      when(() => mockCode.redirectUri)
          .thenReturn('http://app.example.com/callback');
      when(() => mockCode.clientId).thenReturn('my-app');
      when(() => mockCode.codeChallenge).thenReturn(null);
      when(() => mockCode.codeChallengeMethod).thenReturn(null);
      when(() => mockCode.userId).thenReturn(1);
      when(() => mockCode.scope).thenReturn('user/*.*');

      when(() => mockDb.getAuthorizationCode('valid-code'))
          .thenAnswer((_) async => mockCode);
      when(() => mockDb.markAuthorizationCodeUsed('valid-code'))
          .thenAnswer((_) async {});

      final mockUser = MockUser();
      when(() => mockUser.id).thenReturn(1);
      when(() => mockUser.username).thenReturn('testuser');
      when(() => mockUser.role).thenReturn('admin');
      when(() => mockUser.active).thenReturn(true);
      when(() => mockUser.scopes).thenReturn(null);

      when(() => mockDb.getUserById(1)).thenAnswer((_) async => mockUser);

      final request = _makeRequest({
        'grant_type': 'authorization_code',
        'code': 'valid-code',
        'redirect_uri': 'http://app.example.com/callback',
        'client_id': 'my-app',
      });

      final response = await refreshHandler(request, mockDb, jwtService);
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['access_token'], isNotNull);
      expect(body['refresh_token'], isNotNull);
      expect(body['token_type'], 'Bearer');
      expect(body['scope'], 'user/*.*');
      expect(body['username'], 'testuser');

      // Verify the access token is valid
      final payload =
          jwtService.verifyToken(body['access_token'] as String);
      expect(payload, isNotNull);
      expect(payload!['username'], 'testuser');
    });

    test('exchanges valid code with PKCE', () async {
      // Generate a proper PKCE S256 pair
      final codeVerifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      // SHA256 of the verifier, base64url encoded without padding
      // Pre-computed: echo -n "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk" | sha256sum
      // Then base64url encode

      // Compute the expected S256 challenge
      final bytes = utf8.encode(codeVerifier);
      final digest = sha256.convert(bytes);
      final codeChallenge = base64Url.encode(digest.bytes).replaceAll('=', '');

      final mockCode = MockAuthorizationCode();
      when(() => mockCode.code).thenReturn('pkce-valid');
      when(() => mockCode.used).thenReturn(false);
      when(() => mockCode.expiresAt)
          .thenReturn(DateTime.now().add(const Duration(minutes: 5)));
      when(() => mockCode.redirectUri)
          .thenReturn('http://app.example.com/callback');
      when(() => mockCode.clientId).thenReturn('my-app');
      when(() => mockCode.codeChallenge).thenReturn(codeChallenge);
      when(() => mockCode.codeChallengeMethod).thenReturn('S256');
      when(() => mockCode.userId).thenReturn(1);
      when(() => mockCode.scope).thenReturn('user/*.*');

      when(() => mockDb.getAuthorizationCode('pkce-valid'))
          .thenAnswer((_) async => mockCode);
      when(() => mockDb.markAuthorizationCodeUsed('pkce-valid'))
          .thenAnswer((_) async {});

      final mockUser = MockUser();
      when(() => mockUser.id).thenReturn(1);
      when(() => mockUser.username).thenReturn('testuser');
      when(() => mockUser.role).thenReturn('admin');
      when(() => mockUser.active).thenReturn(true);
      when(() => mockUser.scopes).thenReturn(null);

      when(() => mockDb.getUserById(1)).thenAnswer((_) async => mockUser);

      final request = _makeRequest({
        'grant_type': 'authorization_code',
        'code': 'pkce-valid',
        'redirect_uri': 'http://app.example.com/callback',
        'client_id': 'my-app',
        'code_verifier': codeVerifier,
      });

      final response = await refreshHandler(request, mockDb, jwtService);
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['access_token'], isNotNull);
      expect(body['token_type'], 'Bearer');
    });
  });
}
