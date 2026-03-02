import 'dart:convert';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/refresh_handler.dart';
import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:shelf/shelf.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

class MockUser extends Mock implements User {}

void main() {
  group('refreshHandler', () {
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

    test('returns 400 for unsupported grant_type', () async {
      final request =
          _makeRequest({'grant_type': 'authorization_code', 'code': 'abc'});

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
      // Generate an access token (not a refresh token)
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
      expect(body['token'], isNotNull);
      expect(body['refresh_token'], isNotNull);
      expect(body['token_type'], 'Bearer');
      expect(body['username'], 'testuser');
      expect(body['role'], 'admin');

      // Verify the new access token is valid
      final newPayload = jwtService.verifyToken(body['token'] as String);
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
      final newPayload = jwtService.verifyToken(body['token'] as String);
      expect(newPayload!['patient'], 'pat-123');
    });
  });
}
