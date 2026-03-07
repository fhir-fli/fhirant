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
    // Default stubs for lockout methods
    when(() => mockDb.incrementFailedLogins(any())).thenAnswer((_) async => 1);
    when(() => mockDb.resetFailedLogins(any())).thenAnswer((_) async {});
    when(() => mockDb.lockAccount(any(), any())).thenAnswer((_) async {});
    when(() => mockDb.unlockAccount(any())).thenAnswer((_) async {});
  });

  group('registerHandler', () {
    test('first-user bootstrap creates admin', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/register'),
        body: jsonEncode({
          'username': 'admin_user',
          'password': 'secureP@ss12',
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
          'password': 'secureP@ss12',
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
          'password': 'secureP@ss12',
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
          'password': 'secureP@ss12',
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
          'password': 'secureP@ss12',
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
          'password': 'secureP@ss12',
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
    /// Creates a standard MockUser with valid credentials and no lockout.
    MockUser _createMockUser({
      int id = 1,
      String username = 'testuser',
      String role = 'clinician',
      bool active = true,
      String password = 'secureP@ss12',
      String? scopes,
      int failedLoginCount = 0,
      DateTime? lockedUntil,
    }) {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hashPassword(password, salt);
      final mockUser = MockUser();
      when(() => mockUser.id).thenReturn(id);
      when(() => mockUser.username).thenReturn(username);
      when(() => mockUser.role).thenReturn(role);
      when(() => mockUser.active).thenReturn(active);
      when(() => mockUser.salt).thenReturn(salt);
      when(() => mockUser.passwordHash).thenReturn(hash);
      when(() => mockUser.scopes).thenReturn(scopes);
      when(() => mockUser.failedLoginCount).thenReturn(failedLoginCount);
      when(() => mockUser.lockedUntil).thenReturn(lockedUntil);
      return mockUser;
    }

    test('valid login returns JWT', () async {
      final mockUser = _createMockUser();

      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/login'),
        body: jsonEncode({
          'username': 'testuser',
          'password': 'secureP@ss12',
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
          'password': 'secureP@ss12',
        }),
      );

      when(() => mockDb.getUserByUsername('nobody'))
          .thenAnswer((_) async => null);

      final response = await loginHandler(request, mockDb, jwtService);

      expect(response.statusCode, equals(401));
    });

    test('wrong password returns 401', () async {
      final mockUser = _createMockUser(password: 'correctPassword');

      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/login'),
        body: jsonEncode({
          'username': 'testuser',
          'password': 'wrongPassword1',
        }),
      );

      when(() => mockDb.getUserByUsername('testuser'))
          .thenAnswer((_) async => mockUser);

      final response = await loginHandler(request, mockDb, jwtService);

      expect(response.statusCode, equals(401));
    });

    test('deactivated user returns 403', () async {
      final mockUser = _createMockUser(active: false);

      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/login'),
        body: jsonEncode({
          'username': 'testuser',
          'password': 'secureP@ss12',
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

    test('locked account returns 423', () async {
      final mockUser = _createMockUser(
        lockedUntil: DateTime.now().add(const Duration(minutes: 10)),
      );

      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/login'),
        body: jsonEncode({
          'username': 'testuser',
          'password': 'secureP@ss12',
        }),
      );

      when(() => mockDb.getUserByUsername('testuser'))
          .thenAnswer((_) async => mockUser);

      final response = await loginHandler(request, mockDb, jwtService);

      expect(response.statusCode, equals(423));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], contains('locked'));
    });

    test('expired lockout auto-unlocks and allows login', () async {
      final mockUser = _createMockUser(
        lockedUntil: DateTime.now().subtract(const Duration(minutes: 1)),
        failedLoginCount: 5,
      );

      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/login'),
        body: jsonEncode({
          'username': 'testuser',
          'password': 'secureP@ss12',
        }),
      );

      when(() => mockDb.getUserByUsername('testuser'))
          .thenAnswer((_) async => mockUser);
      when(() => mockDb.updateLastLogin(1)).thenAnswer((_) async {});

      final response = await loginHandler(request, mockDb, jwtService);

      expect(response.statusCode, equals(200));
      // Verify resetFailedLogins was called (auto-unlock)
      verify(() => mockDb.resetFailedLogins(1)).called(greaterThanOrEqualTo(1));
    });

    test('failed login increments counter', () async {
      final mockUser = _createMockUser(password: 'correctPassword');

      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/login'),
        body: jsonEncode({
          'username': 'testuser',
          'password': 'wrongPassword1',
        }),
      );

      when(() => mockDb.getUserByUsername('testuser'))
          .thenAnswer((_) async => mockUser);

      final response = await loginHandler(request, mockDb, jwtService);

      expect(response.statusCode, equals(401));
      verify(() => mockDb.incrementFailedLogins(1)).called(1);
    });

    test('account locked after max failed attempts', () async {
      final mockUser = _createMockUser(
        password: 'correctPassword',
        failedLoginCount: 4,
      );

      // This is the 5th failed attempt — should trigger lockout
      when(() => mockDb.incrementFailedLogins(1)).thenAnswer((_) async => 5);

      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/login'),
        body: jsonEncode({
          'username': 'testuser',
          'password': 'wrongPassword1',
        }),
      );

      when(() => mockDb.getUserByUsername('testuser'))
          .thenAnswer((_) async => mockUser);

      final response = await loginHandler(request, mockDb, jwtService);

      expect(response.statusCode, equals(423));
      verify(() => mockDb.lockAccount(1, any())).called(1);
    });

    test('successful login resets failed count', () async {
      final mockUser = _createMockUser(failedLoginCount: 3);

      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/login'),
        body: jsonEncode({
          'username': 'testuser',
          'password': 'secureP@ss12',
        }),
      );

      when(() => mockDb.getUserByUsername('testuser'))
          .thenAnswer((_) async => mockUser);
      when(() => mockDb.updateLastLogin(1)).thenAnswer((_) async {});

      final response = await loginHandler(request, mockDb, jwtService);

      expect(response.statusCode, equals(200));
      verify(() => mockDb.resetFailedLogins(1)).called(1);
    });
  });

  group('unlockAccountHandler', () {
    test('non-admin returns 403', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/admin/unlock/1'),
        context: {
          'auth_user': {'userId': 2, 'username': 'nurse', 'role': 'clinician'}
        },
      );

      final response = await unlockAccountHandler(request, 1, mockDb);

      expect(response.statusCode, equals(403));
    });

    test('unknown user returns 404', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/admin/unlock/999'),
        context: {
          'auth_user': {'userId': 1, 'username': 'admin', 'role': 'admin'}
        },
      );

      when(() => mockDb.getUserById(999)).thenAnswer((_) async => null);

      final response = await unlockAccountHandler(request, 999, mockDb);

      expect(response.statusCode, equals(404));
    });

    test('admin can unlock account', () async {
      final mockUser = MockUser();
      when(() => mockUser.id).thenReturn(2);
      when(() => mockUser.username).thenReturn('lockeduser');

      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/admin/unlock/2'),
        context: {
          'auth_user': {'userId': 1, 'username': 'admin', 'role': 'admin'}
        },
      );

      when(() => mockDb.getUserById(2)).thenAnswer((_) async => mockUser);

      final response = await unlockAccountHandler(request, 2, mockDb);

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['message'], contains('unlocked'));
      verify(() => mockDb.unlockAccount(2)).called(1);
    });
  });
}
