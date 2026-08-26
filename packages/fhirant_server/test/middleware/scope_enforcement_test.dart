import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/middlewares/auth_middleware.dart';
import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:fhirant_server/src/utils/smart_scopes.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

/// Regression guards for findings F1 and F2 of SECURITY-REVIEW-2026-08-25.md.
///
/// These began as evidence that the two bypasses were real, asserting that the
/// least privileged token DID reach places it should not. Both findings are
/// now fixed, so the expectations are inverted and the file guards the fix.
void main() {
  late JwtService jwtService;
  late MockFhirAntDb mockDb;
  late Middleware middleware;

  setUp(() {
    jwtService = JwtService('test-secret-key');
    mockDb = MockFhirAntDb();
    when(() => mockDb.isTokenRevoked(any())).thenAnswer((_) async => false);
    middleware = authMiddleware(jwtService, mockDb);
  });

  /// Reports whether the request reached the handler, i.e. was authorised.
  Future<bool> reaches(String method, String path, String token) async {
    var arrived = false;
    final handler = middleware((request) {
      arrived = true;
      return Response.ok('ok');
    });
    await handler(
      Request(
        method,
        Uri.parse('http://localhost:8080/$path'),
        headers: {'authorization': 'Bearer $token'},
      ),
    );
    return arrived;
  }

  /// The least privileged account the server can issue: read-only, scoped to a
  /// single patient and a single resource type.
  ///
  /// The scope is deliberately valid SMART v2. An invalid one would now be
  /// rejected by the parse check, and every test below would pass for that
  /// reason rather than for the one it claims to be testing.
  String leastPrivilegedToken() => jwtService.generateToken(
        userId: 2,
        username: 'scoped',
        role: 'readonly',
        scopes: ['patient/Observation.rs'],
        patientId: 'patient-A',
      );

  group('the scope check does what it claims for resource paths', () {
    test('a read-only token cannot write a resource', () async {
      final token = jwtService.generateToken(
        userId: 3,
        username: 'ro',
        role: 'readonly',
        scopes: ['user/Patient.read'],
      );
      expect(await reaches('POST', 'Patient', token), isFalse);
    });

    test('a token scoped to one resource type cannot read another', () async {
      final token = jwtService.generateToken(
        userId: 3,
        username: 'ro',
        role: 'readonly',
        scopes: ['user/Observation.read'],
      );
      expect(await reaches('GET', 'Patient/123', token), isFalse);
    });

    test('a read-only token cannot reach a privileged system operation',
        () async {
      final token = jwtService.generateToken(
        userId: 3,
        username: 'ro',
        role: 'readonly',
        scopes: ['user/Patient.read'],
      );
      expect(await reaches('POST', r'$backup', token), isFalse);
    });
  });

  group(r'F1: root-level $ operations are gated deny-by-default', () {
    // resourceTypeFromPath returns null for a $-prefixed first segment, so the
    // resource-scope check cannot cover these. They used to fall through it
    // entirely; they are now gated on their own.
    for (final op in [r'$fhirpath', r'$cql', r'$immds-forecast']) {
      test('a narrowly scoped token is refused $op', () async {
        expect(
          await reaches('POST', op, leastPrivilegedToken()),
          isFalse,
          reason: '$op can return data the request does not name',
        );
      });
    }

    test(r'$fhirpath is no longer a whole-database read primitive', () async {
      // fhirpath_handler.dart:67 fetches any resource by type and id from the
      // database. The fix is that a token scoped to patient-A and Observation
      // never reaches it.
      final reached =
          await reaches('POST', r'$fhirpath', leastPrivilegedToken());
      expect(reached, isFalse);
    });

    test('a patient-context token is refused even with a wildcard scope',
        () async {
      // patient/*.rs parses and is broad, but nothing downstream confines the
      // result to that patient, so the patient context is refused outright.
      final token = jwtService.generateToken(
        userId: 5,
        username: 'patient-app',
        role: 'readonly',
        scopes: ['patient/*.rs'],
        patientId: 'patient-A',
      );
      expect(await reaches('POST', r'$fhirpath', token), isFalse);
    });

    test('a clinician with user/*.rs may still use them', () async {
      // The gate must not break the operations for the accounts that are
      // meant to have them.
      final token = jwtService.generateToken(
        userId: 6,
        username: 'clinician',
        role: 'clinician',
        scopes: ['user/*.rs'],
      );
      expect(await reaches('POST', r'$fhirpath', token), isTrue);
      expect(await reaches('POST', r'$cql', token), isTrue);
    });

    test('operations that touch no stored data stay open to any account',
        () async {
      // $validate and $transform work only on what the caller posted.
      for (final op in [r'$validate', r'$transform']) {
        expect(
          await reaches('POST', op, leastPrivilegedToken()),
          isTrue,
          reason: '$op reads nothing from the database',
        );
      }
    });
  });

  group('F2: an unparseable scope is dropped, not rejected', () {
    // SmartScope.parse accepts only SMART v2 permission letters (c r u d s *).
    // A v1 scope such as `patient/*.read` fails to parse and is skipped by
    // every consumer — isAuthorized, hasPatientScopes and isPatientOnlyContext
    // all iterate the parsed subset. Dropping a scope that NARROWS access is
    // not fail-closed; it is fail-open by omission.
    test('a v1 scope does not parse', () {
      expect(SmartScope.parse('patient/*.read'), isNull);
      expect(SmartScope.parse('patient/*.rs'), isNotNull);
    });

    test(
        'BYPASS: a v1 patient scope beside a v2 user scope loses the '
        'patient restriction', () {
      // The issuer intended "this patient, read only". What survives is
      // "any patient, read and search".
      const intended = ['patient/*.read', 'user/*.rs'];

      expect(
        SmartScopeEnforcer.hasPatientScopes(intended),
        isFalse,
        reason: 'the middleware therefore never demands a patient claim',
      );
      expect(
        SmartScopeEnforcer.isPatientOnlyContext(intended),
        isFalse,
        reason: 'so extractPatientContext returns null and no compartment '
            'filter is applied by resource_handler',
      );
      expect(
        SmartScopeEnforcer.isAuthorized(intended, 'Patient', 'r'),
        isTrue,
        reason: 'while the surviving user scope still grants the read',
      );

      // Which is why the middleware now refuses the token outright rather
      // than acting on the half of it that happened to parse.
      expect(SmartScopeEnforcer.allScopesParse(intended), isFalse);
    });

    test('a token carrying an unparseable scope is refused', () async {
      final token = jwtService.generateToken(
        userId: 7,
        username: 'mixed',
        role: 'readonly',
        scopes: ['patient/*.read', 'user/*.rs'],
        patientId: 'patient-A',
      );
      expect(
        await reaches('GET', 'Patient/patient-B', token),
        isFalse,
        reason: 'the narrowing scope did not parse, so the token is rejected '
            'rather than silently widened',
      );
    });

    test('a token whose scopes all parse is unaffected', () async {
      final token = jwtService.generateToken(
        userId: 8,
        username: 'ok',
        role: 'readonly',
        scopes: ['user/*.rs'],
      );
      expect(await reaches('GET', 'Patient/patient-B', token), isTrue);
    });

    test('a token carrying ONLY unparseable scopes is denied, which is right',
        () {
      // Worth pinning: the failure mode above comes from MIXING, not from
      // dropping alone. Alone, the drop leaves nothing and access is refused.
      expect(
        SmartScopeEnforcer.isAuthorized(['patient/*.read'], 'Patient', 'r'),
        isFalse,
      );
    });
  });

  group('measured: what the scope check already stops', () {
    test('a patient-scoped token cannot reach system history', () async {
      // `_history` needs the search permission, which `.read` does not grant
      // and `patient/*.rs` grants only within the patient context check.
      expect(
        await reaches('GET', '_history', leastPrivilegedToken()),
        isFalse,
      );
    });

    test("a patient-scoped token cannot read another patient's compartment",
        () async {
      final reached = await reaches(
        'GET',
        'Patient/patient-B/Observation',
        leastPrivilegedToken(),
      );
      expect(reached, isFalse);
    });
  });
}
