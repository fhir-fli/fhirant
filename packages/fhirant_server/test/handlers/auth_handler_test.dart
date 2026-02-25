import 'dart:convert';

import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:fhirant_server/src/handlers/register_handler.dart';
import 'package:fhirant_server/src/handlers/login_handler.dart';
import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

class MockRequest extends Mock implements Request {}

class MockUser extends Mock implements User {}

void main() {
  late MockFhirAntDb mockDb;
  late JwtService jwtService;

  setUp(() {
    mockDb = MockFhirAntDb();
    jwtService = JwtService('test-secret-key');
  });

  group('registerHandler', () {
    test('first-user bootstrap creates admin', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/register'),
        body: jsonEncode({
          'username': 'admin_user',
          'password': 'secureP@ss1',
          'role': 'clinician', // should be overridden to admin
        }),
      );

      when(() => mockDb.getUserCount()).thenAnswer((_) async => 0);
      when(() => mockDb.getUserByUsername('admin_user'))
          .thenAnswer((_) async => null);
      when(() => mockDb.createUser(
            username: any(named: 'username'),
            passwordHash: any(named: 'passwordHash'),
            salt: any(named: 'salt'),
            role: any(named: 'role'),
            scopes: any(named: 'scopes'),
          )).thenAnswer((_) async => 1);

      final response = await registerHandler(request, mockDb);

      expect(response.statusCode, equals(201));
      final body = jsonDecode(await response.readAsString());
      expect(body['role'], equals('admin'));
      expect(body['username'], equals('admin_user'));

      // Verify createUser was called with role=admin
      final captured = verify(() => mockDb.createUser(
            username: captureAny(named: 'username'),
            passwordHash: captureAny(named: 'passwordHash'),
            salt: captureAny(named: 'salt'),
            role: captureAny(named: 'role'),
            scopes: captureAny(named: 'scopes'),
          )).captured;
      expect(captured[3], equals('admin'));
    });

    test('non-admin rejected when users exist', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/register'),
        body: jsonEncode({
          'username': 'new_user',
          'password': 'secureP@ss1',
        }),
        context: {}, // no auth_user
      );

      when(() => mockDb.getUserCount()).thenAnswer((_) async => 1);

      final response = await registerHandler(request, mockDb);

      expect(response.statusCode, equals(403));
    });

    test('admin can register new user', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/register'),
        body: jsonEncode({
          'username': 'new_clinician',
          'password': 'secureP@ss1',
          'role': 'clinician',
        }),
        context: {
          'auth_user': {'userId': 1, 'username': 'admin', 'role': 'admin'}
        },
      );

      when(() => mockDb.getUserCount()).thenAnswer((_) async => 1);
      when(() => mockDb.getUserByUsername('new_clinician'))
          .thenAnswer((_) async => null);
      when(() => mockDb.createUser(
            username: any(named: 'username'),
            passwordHash: any(named: 'passwordHash'),
            salt: any(named: 'salt'),
            role: any(named: 'role'),
            scopes: any(named: 'scopes'),
          )).thenAnswer((_) async => 2);

      final response = await registerHandler(request, mockDb);

      expect(response.statusCode, equals(201));
      final body = jsonDecode(await response.readAsString());
      expect(body['role'], equals('clinician'));
    });

    test('missing username returns 400', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/register'),
        body: jsonEncode({
          'password': 'secureP@ss1',
        }),
      );

      final response = await registerHandler(request, mockDb);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('Username'));
    });

    test('short password returns 400', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/register'),
        body: jsonEncode({
          'username': 'validuser',
          'password': 'short',
        }),
      );

      final response = await registerHandler(request, mockDb);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('Password'));
    });

    test('duplicate username returns 409', () async {
      final mockUser = MockUser();
      when(() => mockUser.id).thenReturn(1);
      when(() => mockUser.username).thenReturn('existing');

      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/register'),
        body: jsonEncode({
          'username': 'existing',
          'password': 'secureP@ss1',
        }),
      );

      when(() => mockDb.getUserCount()).thenAnswer((_) async => 0);
      when(() => mockDb.getUserByUsername('existing'))
          .thenAnswer((_) async => mockUser);

      final response = await registerHandler(request, mockDb);

      expect(response.statusCode, equals(409));
    });

    test('invalid role returns 400', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/register'),
        body: jsonEncode({
          'username': 'validuser',
          'password': 'secureP@ss1',
          'role': 'superadmin',
        }),
      );

      final response = await registerHandler(request, mockDb);

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('Invalid role'));
    });
  });

  group('loginHandler', () {
    test('valid login returns JWT', () async {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hashPassword('secureP@ss1', salt);

      final mockUser = MockUser();
      when(() => mockUser.id).thenReturn(1);
      when(() => mockUser.username).thenReturn('testuser');
      when(() => mockUser.role).thenReturn('clinician');
      when(() => mockUser.active).thenReturn(true);
      when(() => mockUser.salt).thenReturn(salt);
      when(() => mockUser.passwordHash).thenReturn(hash);
      when(() => mockUser.scopes).thenReturn(null);

      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/login'),
        body: jsonEncode({
          'username': 'testuser',
          'password': 'secureP@ss1',
        }),
      );

      when(() => mockDb.getUserByUsername('testuser'))
          .thenAnswer((_) async => mockUser);
      when(() => mockDb.updateLastLogin(1)).thenAnswer((_) async {});

      final response = await loginHandler(request, mockDb, jwtService);

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['token'], isA<String>());
      expect(body['username'], equals('testuser'));
      expect(body['role'], equals('clinician'));

      // Verify the token is valid
      final payload = jwtService.verifyToken(body['token']);
      expect(payload, isNotNull);
      expect(payload!['username'], equals('testuser'));
    });

    test('unknown user returns 401', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/login'),
        body: jsonEncode({
          'username': 'nobody',
          'password': 'secureP@ss1',
        }),
      );

      when(() => mockDb.getUserByUsername('nobody'))
          .thenAnswer((_) async => null);

      final response = await loginHandler(request, mockDb, jwtService);

      expect(response.statusCode, equals(401));
    });

    test('wrong password returns 401', () async {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hashPassword('correctPassword', salt);

      final mockUser = MockUser();
      when(() => mockUser.id).thenReturn(1);
      when(() => mockUser.username).thenReturn('testuser');
      when(() => mockUser.active).thenReturn(true);
      when(() => mockUser.salt).thenReturn(salt);
      when(() => mockUser.passwordHash).thenReturn(hash);

      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/login'),
        body: jsonEncode({
          'username': 'testuser',
          'password': 'wrongPassword',
        }),
      );

      when(() => mockDb.getUserByUsername('testuser'))
          .thenAnswer((_) async => mockUser);

      final response = await loginHandler(request, mockDb, jwtService);

      expect(response.statusCode, equals(401));
    });

    test('deactivated user returns 403', () async {
      final mockUser = MockUser();
      when(() => mockUser.id).thenReturn(1);
      when(() => mockUser.username).thenReturn('testuser');
      when(() => mockUser.active).thenReturn(false);

      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/login'),
        body: jsonEncode({
          'username': 'testuser',
          'password': 'secureP@ss1',
        }),
      );

      when(() => mockDb.getUserByUsername('testuser'))
          .thenAnswer((_) async => mockUser);

      final response = await loginHandler(request, mockDb, jwtService);

      expect(response.statusCode, equals(403));
    });

    test('missing login fields returns 400', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/login'),
        body: jsonEncode({'username': 'testuser'}),
      );

      final response = await loginHandler(request, mockDb, jwtService);

      expect(response.statusCode, equals(400));
    });
  });
}
