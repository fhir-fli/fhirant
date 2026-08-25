import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/middlewares/auth_middleware.dart';
import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:fhirant_server/src/utils/smart_scopes.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

/// Evidence for findings F1 and F2 of SECURITY-REVIEW-2026-08-25.md.
///
/// These tests document what the authorisation layer does *today*, so the
/// findings rest on observed behaviour rather than on reading. Each one that
/// asserts a bypass is marked, and is expected to be inverted when the finding
/// is fixed — at which point it becomes the regression test.
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

  /// The least privileged account the server can issue: read-only, and scoped
  /// to a single patient.
  String leastPrivilegedToken() => jwtService.generateToken(
        userId: 2,
        username: 'scoped',
        role: 'readonly',
        scopes: ['patient/Observation.read'],
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

  group(r'F1: root-level $ operations are not scope-checked', () {
    // resourceTypeFromPath returns null for a $-prefixed first segment, so the
    // scope check never runs; and these are not in the privileged list, so the
    // system-level gate does not run either. The result is authenticated but
    // unauthorised access.
    for (final op in [r'$fhirpath', r'$cql', r'$transform', r'$validate']) {
      test('BYPASS: the least privileged token reaches $op', () async {
        expect(
          await reaches('POST', op, leastPrivilegedToken()),
          isTrue,
          reason: 'if this now fails, F1 has been fixed — invert the '
              'expectation and keep it as the regression test',
        );
      });
    }

    test(r'BYPASS: $fhirpath is a whole-database read primitive', () async {
      // fhirpath_handler.dart:67 fetches any resource by type and id from the
      // database. Reaching the handler at all is the finding: a token scoped
      // to patient-A and to Observation only gets to name any resource.
      final reached =
          await reaches('POST', r'$fhirpath', leastPrivilegedToken());
      expect(reached, isTrue);
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
