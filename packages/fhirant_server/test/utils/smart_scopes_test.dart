import 'package:test/test.dart';
import 'package:fhirant_server/src/utils/smart_scopes.dart';

void main() {
  group('SmartScope.parse', () {
    test('parses user/Patient.cruds', () {
      final scope = SmartScope.parse('user/Patient.cruds');
      expect(scope, isNotNull);
      expect(scope!.context, 'user');
      expect(scope.resourceType, 'Patient');
      expect(scope.permissions, containsAll(['c', 'r', 'u', 'd', 's']));
    });

    test('parses user/Patient.rs (read+search)', () {
      final scope = SmartScope.parse('user/Patient.rs');
      expect(scope, isNotNull);
      expect(scope!.permissions, equals({'r', 's'}));
    });

    test('parses system/*.*', () {
      final scope = SmartScope.parse('system/*.*');
      expect(scope, isNotNull);
      expect(scope!.context, 'system');
      expect(scope.resourceType, '*');
      expect(scope.permissions, containsAll(['c', 'r', 'u', 'd', 's']));
    });

    test('parses patient/Observation.r', () {
      final scope = SmartScope.parse('patient/Observation.r');
      expect(scope, isNotNull);
      expect(scope!.context, 'patient');
      expect(scope.resourceType, 'Observation');
      expect(scope.permissions, equals({'r'}));
    });

    test('returns null for invalid context', () {
      expect(SmartScope.parse('admin/Patient.r'), isNull);
    });

    test('returns null for missing dot', () {
      expect(SmartScope.parse('user/Patient'), isNull);
    });

    test('returns null for empty permissions', () {
      expect(SmartScope.parse('user/Patient.'), isNull);
    });

    test('returns null for invalid permission character', () {
      expect(SmartScope.parse('user/Patient.x'), isNull);
    });

    test('returns null for empty string', () {
      expect(SmartScope.parse(''), isNull);
    });

    test('returns null for no slash', () {
      expect(SmartScope.parse('Patient.r'), isNull);
    });
  });

  group('SmartScopeEnforcer.defaultScopesForRole', () {
    test('admin gets system/*.*', () {
      final scopes = SmartScopeEnforcer.defaultScopesForRole('admin');
      expect(scopes, equals(['system/*.*']));
    });

    test('clinician gets user/*.*', () {
      final scopes = SmartScopeEnforcer.defaultScopesForRole('clinician');
      expect(scopes, equals(['user/*.*']));
    });

    test('readonly gets user/*.rs', () {
      final scopes = SmartScopeEnforcer.defaultScopesForRole('readonly');
      expect(scopes, equals(['user/*.rs']));
    });

    test('unknown role defaults to readonly', () {
      final scopes = SmartScopeEnforcer.defaultScopesForRole('unknown');
      expect(scopes, equals(['user/*.rs']));
    });
  });

  group('SmartScopeEnforcer.isAuthorized', () {
    test('wildcard type + wildcard perm authorizes anything', () {
      expect(
        SmartScopeEnforcer.isAuthorized(['system/*.*'], 'Patient', 'c'),
        isTrue,
      );
      expect(
        SmartScopeEnforcer.isAuthorized(['system/*.*'], 'Observation', 'd'),
        isTrue,
      );
    });

    test('specific type only matches that type', () {
      expect(
        SmartScopeEnforcer.isAuthorized(['user/Patient.r'], 'Patient', 'r'),
        isTrue,
      );
      expect(
        SmartScopeEnforcer.isAuthorized(
            ['user/Patient.r'], 'Observation', 'r'),
        isFalse,
      );
    });

    test('permission subset enforced', () {
      expect(
        SmartScopeEnforcer.isAuthorized(['user/Patient.rs'], 'Patient', 'r'),
        isTrue,
      );
      expect(
        SmartScopeEnforcer.isAuthorized(['user/Patient.rs'], 'Patient', 's'),
        isTrue,
      );
      expect(
        SmartScopeEnforcer.isAuthorized(['user/Patient.rs'], 'Patient', 'c'),
        isFalse,
      );
      expect(
        SmartScopeEnforcer.isAuthorized(['user/Patient.rs'], 'Patient', 'd'),
        isFalse,
      );
    });

    test('multiple scopes — any match authorizes', () {
      final scopes = ['user/Patient.r', 'user/Observation.cruds'];
      expect(
        SmartScopeEnforcer.isAuthorized(scopes, 'Observation', 'c'),
        isTrue,
      );
      expect(
        SmartScopeEnforcer.isAuthorized(scopes, 'Patient', 'r'),
        isTrue,
      );
      expect(
        SmartScopeEnforcer.isAuthorized(scopes, 'Patient', 'c'),
        isFalse,
      );
    });

    test('invalid scope strings are skipped', () {
      expect(
        SmartScopeEnforcer.isAuthorized(
            ['garbage', 'user/Patient.r'], 'Patient', 'r'),
        isTrue,
      );
    });

    test('empty scopes denies everything', () {
      expect(
        SmartScopeEnforcer.isAuthorized([], 'Patient', 'r'),
        isFalse,
      );
    });
  });

  group('SmartScopeEnforcer.methodToPermission', () {
    test('GET type-level is search', () {
      expect(SmartScopeEnforcer.methodToPermission('GET', '/Patient'), 's');
    });

    test('GET instance-level is read', () {
      expect(SmartScopeEnforcer.methodToPermission('GET', '/Patient/123'), 'r');
    });

    test('POST type-level is create', () {
      expect(SmartScopeEnforcer.methodToPermission('POST', '/Patient'), 'c');
    });

    test('PUT is update', () {
      expect(
          SmartScopeEnforcer.methodToPermission('PUT', '/Patient/123'), 'u');
    });

    test('PATCH is update', () {
      expect(
          SmartScopeEnforcer.methodToPermission('PATCH', '/Patient/123'), 'u');
    });

    test('DELETE is delete', () {
      expect(
          SmartScopeEnforcer.methodToPermission('DELETE', '/Patient/123'), 'd');
    });

    test('auth routes return null', () {
      expect(SmartScopeEnforcer.methodToPermission('POST', '/auth/login'),
          isNull);
    });

    test('metadata returns null', () {
      expect(
          SmartScopeEnforcer.methodToPermission('GET', '/metadata'), isNull);
    });

    test('.well-known returns null', () {
      expect(
          SmartScopeEnforcer.methodToPermission(
              'GET', '/.well-known/smart-configuration'),
          isNull);
    });
  });

  group('SmartScopeEnforcer.resourceTypeFromPath', () {
    test('extracts Patient from /Patient', () {
      expect(SmartScopeEnforcer.resourceTypeFromPath('/Patient'), 'Patient');
    });

    test('extracts Patient from /Patient/123', () {
      expect(
          SmartScopeEnforcer.resourceTypeFromPath('/Patient/123'), 'Patient');
    });

    test('returns null for root', () {
      expect(SmartScopeEnforcer.resourceTypeFromPath('/'), isNull);
    });

    test('returns null for \$operations', () {
      expect(SmartScopeEnforcer.resourceTypeFromPath('/\$export'), isNull);
    });

    test('returns null for auth', () {
      expect(SmartScopeEnforcer.resourceTypeFromPath('/auth/login'), isNull);
    });

    test('returns null for metadata', () {
      expect(SmartScopeEnforcer.resourceTypeFromPath('/metadata'), isNull);
    });
  });
}
