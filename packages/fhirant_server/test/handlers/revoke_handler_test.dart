import 'dart:convert';

import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/revoke_handler.dart';
import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:fhirant_server/src/utils/token_hasher.dart';
import 'package:shelf/shelf.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

void main() {
  late MockFhirAntDb mockDb;
  late JwtService jwtService;

  setUp(() {
    mockDb = MockFhirAntDb();
    jwtService = JwtService('test-secret');
    when(() => mockDb.revokeToken(any(), any())).thenAnswer((_) async {});
  });

  group('revokeHandler', () {
    test('revokes valid access token (JSON body)', () async {
      final token = jwtService.generateToken(
        userId: 1,
        username: 'testuser',
        role: 'admin',
      );

      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/revoke'),
        body: jsonEncode({'token': token}),
      );

      final response = await revokeHandler(request, mockDb);
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['status'], 'revoked');

      final expectedHash = TokenHasher.hash(token);
      verify(() => mockDb.revokeToken(expectedHash, any())).called(1);
    });

    test('revokes valid refresh token', () async {
      final token = jwtService.generateRefreshToken(
        userId: 1,
        username: 'testuser',
        role: 'admin',
      );

      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/revoke'),
        body: jsonEncode({'token': token}),
      );

      final response = await revokeHandler(request, mockDb);
      expect(response.statusCode, 200);

      verify(() => mockDb.revokeToken(TokenHasher.hash(token), any()))
          .called(1);
    });

    test('returns 400 when token field is missing', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/revoke'),
        body: jsonEncode({'not_a_token': 'value'}),
      );

      final response = await revokeHandler(request, mockDb);
      expect(response.statusCode, 400);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'invalid_request');
    });

    test('returns 200 for garbage/non-JWT token (per RFC 7009)', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/revoke'),
        body: jsonEncode({'token': 'garbage-not-a-jwt'}),
      );

      final response = await revokeHandler(request, mockDb);
      expect(response.statusCode, 200);

      // Still revoked — the hash is stored regardless
      verify(() => mockDb.revokeToken(
              TokenHasher.hash('garbage-not-a-jwt'), any()))
          .called(1);
    });

    test('supports form-encoded body', () async {
      final token = jwtService.generateToken(
        userId: 1,
        username: 'testuser',
        role: 'admin',
      );

      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/revoke'),
        body: 'token=${Uri.encodeComponent(token)}',
      );

      final response = await revokeHandler(request, mockDb);
      expect(response.statusCode, 200);

      verify(() => mockDb.revokeToken(TokenHasher.hash(token), any()))
          .called(1);
    });
  });

  group('logoutHandler', () {
    test('revokes access token from Authorization header', () async {
      final token = jwtService.generateToken(
        userId: 1,
        username: 'testuser',
        role: 'admin',
      );

      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/logout'),
        headers: {'authorization': 'Bearer $token'},
      );

      final response = await logoutHandler(request, mockDb);
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['status'], 'logged_out');

      verify(() => mockDb.revokeToken(TokenHasher.hash(token), any()))
          .called(1);
    });

    test('revokes both access and refresh tokens', () async {
      final accessToken = jwtService.generateToken(
        userId: 1,
        username: 'testuser',
        role: 'admin',
      );
      final refreshToken = jwtService.generateRefreshToken(
        userId: 1,
        username: 'testuser',
        role: 'admin',
      );

      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/logout'),
        headers: {'authorization': 'Bearer $accessToken'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );

      final response = await logoutHandler(request, mockDb);
      expect(response.statusCode, 200);

      // Both tokens should be revoked
      verify(() => mockDb.revokeToken(TokenHasher.hash(accessToken), any()))
          .called(1);
      verify(() => mockDb.revokeToken(TokenHasher.hash(refreshToken), any()))
          .called(1);
    });

    test('returns 200 with no auth header (graceful no-op)', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/logout'),
      );

      final response = await logoutHandler(request, mockDb);
      expect(response.statusCode, 200);

      verifyNever(() => mockDb.revokeToken(any(), any()));
    });

    test('revokes only refresh_token from body when no auth header',
        () async {
      final refreshToken = jwtService.generateRefreshToken(
        userId: 1,
        username: 'testuser',
        role: 'admin',
      );

      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/logout'),
        body: jsonEncode({'refresh_token': refreshToken}),
      );

      final response = await logoutHandler(request, mockDb);
      expect(response.statusCode, 200);

      verify(() => mockDb.revokeToken(TokenHasher.hash(refreshToken), any()))
          .called(1);
    });
  });
}
