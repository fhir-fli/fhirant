import 'dart:convert';

import 'package:test/test.dart';
import 'package:shelf/shelf.dart';
import 'package:fhirant_server/src/middlewares/auth_middleware.dart';
import 'package:fhirant_server/src/utils/jwt_service.dart';

void main() {
  late JwtService jwtService;
  late Middleware middleware;

  setUp(() {
    jwtService = JwtService('test-secret-key');
    middleware = authMiddleware(jwtService);
  });

  /// Wraps [middleware] around a simple handler that echoes the auth_user
  /// context as JSON body (or returns 200 with 'ok').
  Handler _createHandler() {
    return middleware((Request request) {
      final authUser = request.context['auth_user'];
      if (authUser != null) {
        return Response.ok(jsonEncode(authUser));
      }
      return Response.ok('ok');
    });
  }

  group('authMiddleware', () {
    test('public routes pass without token', () async {
      final handler = _createHandler();

      // Root
      var response = await handler(
          Request('GET', Uri.parse('http://localhost:8080/')));
      expect(response.statusCode, equals(200));

      // Metadata
      response = await handler(
          Request('GET', Uri.parse('http://localhost:8080/metadata')));
      expect(response.statusCode, equals(200));

      // Auth login
      response = await handler(
          Request('POST', Uri.parse('http://localhost:8080/auth/login')));
      expect(response.statusCode, equals(200));

      // Auth register
      response = await handler(
          Request('POST', Uri.parse('http://localhost:8080/auth/register')));
      expect(response.statusCode, equals(200));

      // Favicon
      response = await handler(
          Request('GET', Uri.parse('http://localhost:8080/favicon.ico')));
      expect(response.statusCode, equals(200));
    });

    test('missing auth header returns 401', () async {
      final handler = _createHandler();

      final response = await handler(
          Request('GET', Uri.parse('http://localhost:8080/Patient')));

      expect(response.statusCode, equals(401));
      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], equals('OperationOutcome'));
    });

    test('invalid token returns 401', () async {
      final handler = _createHandler();

      final response = await handler(Request(
        'GET',
        Uri.parse('http://localhost:8080/Patient'),
        headers: {'authorization': 'Bearer invalid.token.here'},
      ));

      expect(response.statusCode, equals(401));
      final body = jsonDecode(await response.readAsString());
      expect(body['issue'][0]['diagnostics'], contains('invalid or expired'));
    });

    test('valid token injects auth_user into context', () async {
      final handler = _createHandler();

      final token = jwtService.generateToken(
        userId: 1,
        username: 'testuser',
        role: 'clinician',
      );

      final response = await handler(Request(
        'GET',
        Uri.parse('http://localhost:8080/Patient'),
        headers: {'authorization': 'Bearer $token'},
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['username'], equals('testuser'));
      expect(body['role'], equals('clinician'));
    });

    test('readonly blocked on POST', () async {
      final handler = _createHandler();

      final token = jwtService.generateToken(
        userId: 2,
        username: 'reader',
        role: 'readonly',
      );

      final response = await handler(Request(
        'POST',
        Uri.parse('http://localhost:8080/Patient'),
        headers: {'authorization': 'Bearer $token'},
      ));

      expect(response.statusCode, equals(403));
      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], equals('OperationOutcome'));
      expect(body['issue'][0]['diagnostics'], contains('Insufficient scope'));
    });

    test('readonly allowed on GET', () async {
      final handler = _createHandler();

      final token = jwtService.generateToken(
        userId: 2,
        username: 'reader',
        role: 'readonly',
      );

      final response = await handler(Request(
        'GET',
        Uri.parse('http://localhost:8080/Patient'),
        headers: {'authorization': 'Bearer $token'},
      ));

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['username'], equals('reader'));
    });
  });
}
