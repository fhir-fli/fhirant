import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/smart_scopes.dart';
import 'package:shelf/shelf.dart';

/// The authenticated caller, as the middleware established it, and the one
/// set of rules that says what it may touch.
///
/// REVIEW-2026-09-08 §1: the 2026-09-06 set put the patient compartment on
/// the type-level search, the read and `$everything`, each handler asking
/// for it in its own words. Every other way of reaching a resource lacked
/// it: the root path, Bundle entries, history, system search, `$document`,
/// `$evaluate`, conditional create and delete, includes, and the body of a
/// write. So the rules live here once, and the middleware, the Bundle
/// processor and every handler ask this class the same questions:
/// [may] (the scope), [compartmentFor] (the confinement), and
/// [authorizeRequest] (a method and a path, as the middleware sees them).
class Principal {
  Principal({
    required this.userId,
    required this.username,
    required this.role,
    required this.scopes,
    this.patientId,
  }) : _parsed = scopes.map(SmartScope.parse).whereType<SmartScope>().toList();

  /// The caller the middleware put on the request, or null when nothing
  /// authenticated it (dev mode injects a synthetic admin; a handler test
  /// calling a handler directly puts nothing).
  static Principal? of(Request request) {
    final authUser = request.context['auth_user'];
    if (authUser is! Map<String, dynamic>) return null;
    final rawScopes = authUser['scopes'];
    final scopes = rawScopes is List
        ? rawScopes.cast<String>()
        : (authUser['scope'] is String &&
                (authUser['scope'] as String).isNotEmpty)
            ? (authUser['scope'] as String).split(' ')
            : SmartScopeEnforcer.defaultScopesForRole(
                authUser['role'] as String? ?? 'readonly',
              );
    final rawId = authUser['userId'];
    return Principal(
      userId: rawId is int ? rawId : int.tryParse('$rawId') ?? -1,
      username: authUser['username'] as String? ?? '',
      role: authUser['role'] as String? ?? 'readonly',
      scopes: scopes,
      patientId: (authUser['patientId'] ?? authUser['patient']) as String?,
    );
  }

  final int userId;
  final String username;
  final String role;
  final List<String> scopes;

  /// The Patient this caller's `patient/` scopes are about, from the token's
  /// `patient` claim; null for a caller with no patient context.
  final String? patientId;

  final List<SmartScope> _parsed;

  /// Whether a scope grants [permission] (one of c r u d s) on
  /// [resourceType].
  bool may(String resourceType, String permission) =>
      SmartScopeEnforcer.isAuthorized(scopes, resourceType, permission);

  /// The compartment that confines [permission] on [resourceType], or null
  /// when nothing confines it.
  ///
  /// Decided per type and permission, not per token: a type is confined
  /// when every scope that grants the permission on it is a `patient/`
  /// scope, and unconfined when a `user/` or `system/` scope grants it. A
  /// token `patient/Observation.rs user/Practitioner.rs`, the shape of an
  /// ordinary SMART patient app, reads Observations inside its patient's
  /// compartment and Practitioners anywhere. It used to be all or nothing
  /// (`isPatientOnlyContext`): one `user/` scope on any type lifted the
  /// compartment from every type (REVIEW-2026-09-08 row 3).
  ///
  /// A type no scope grants is reported confined when a patient context
  /// exists (the scope check refuses it separately); fail closed.
  CompartmentScope? compartmentFor(String resourceType, String permission) {
    final patient = patientId;
    if (patient == null) return null;
    for (final scope in _parsed) {
      if (scope.resourceType != '*' && scope.resourceType != resourceType) {
        continue;
      }
      if (!scope.permissions.contains(permission)) continue;
      if (scope.context != 'patient') return null;
    }
    return CompartmentScope('Patient', patient);
  }

  /// Whether the caller may read data a request does not name by type: a
  /// `user/` or `system/` scope on every type with `r`.
  bool get mayReadUnscoped =>
      SmartScopeEnforcer.isUnscopedDataAccessAuthorized(scopes, 'r');

  /// Whether the caller holds system-level authority: the admin role or a
  /// `system/` scope.
  bool get isSystem => SmartScopeEnforcer.isSystemAuthorized(scopes, role);

  /// Whether this is the synthetic caller dev mode injects.
  bool get isDevMode => username == 'dev-mode' && userId == -1;

  /// The types among [resourceTypes] this caller may not [permission].
  List<String> unauthorizedTypes(
    Iterable<String> resourceTypes,
    String permission,
  ) =>
      resourceTypes.where((t) => !may(t, permission)).toSet().toList()..sort();
}

/// Authorizes [method] on [path] for [principal] the way the middleware
/// does for a request, and the way a Bundle entry must be authorized too:
/// an entry `PUT Patient/p2` is the request `PUT /Patient/p2` and gets the
/// same answer (REVIEW-2026-09-08 row 2). Returns null when allowed, or the
/// 401/403 response that refuses it.
///
/// [path] is the URL path without a leading slash and without its query;
/// [isEntry] is true for a Bundle entry, where the root path and the root
/// operations do not occur.
Response? authorizeRequest(
  Principal principal,
  String method,
  String path,
) {
  final scopes = principal.scopes;
  // Privileged root-level system operations ($backup/$restore/$export)
  // carry no resource type, so the resource-scope check below never
  // covers them: admin role or an explicit system/ scope.
  if (SmartScopeEnforcer.isPrivilegedSystemOperation(path)) {
    if (!principal.isSystem) {
      return forbidden(
        'This operation requires system-level (admin) privilege.',
      );
    }
  }

  final permission = SmartScopeEnforcer.methodToPermission(method, path);

  // Root-level operations that read stored data the request does not name
  // ($fhirpath, $cql, $immds-forecast): a user- or system-context scope
  // covering all resource types, deny-by-default. The export status and
  // file routes are authorized by their handlers against the job's owner.
  if (SmartScopeEnforcer.isRootDataOperation(path) &&
      !SmartScopeEnforcer.isOwnerCheckedOperation(path)) {
    if (!SmartScopeEnforcer.isUnscopedDataAccessAuthorized(
      scopes,
      permission ?? 'r',
    )) {
      return forbidden(
        'This operation can return data the request does not name, so it '
        'requires a user- or system-context scope covering all resource '
        'types.',
      );
    }
  }

  if (permission != null) {
    final resourceType = SmartScopeEnforcer.resourceTypeFromPath(path);
    // Only enforce scopes for resource-targeted requests. `_history` and
    // `_search` at the root name no type; their handlers check each type
    // they touch.
    if (resourceType != null &&
        resourceType != '_history' &&
        resourceType != '_search') {
      if (!principal.may(resourceType, permission)) {
        return forbidden('Insufficient scope for $permission on $resourceType');
      }
      // If patient/ scopes are present but no patient context, reject
      if (SmartScopeEnforcer.hasPatientScopes(scopes) &&
          principal.patientId == null) {
        return forbidden(
          'patient/ scopes require a patient context (patient claim in JWT)',
        );
      }
    }
  }
  return null;
}

/// A 403 with an OperationOutcome, `application/fhir+json`.
Response forbidden(String diagnostics) =>
    outcomeResponse(403, 'forbidden', diagnostics);

/// A 401 with an OperationOutcome, `application/fhir+json`.
Response unauthorized(String diagnostics) =>
    outcomeResponse(401, 'login', diagnostics);

/// An OperationOutcome response with its content type declared. The
/// middleware's 401/403 bodies used to carry none (REVIEW-2026-09-08 row 19).
Response outcomeResponse(int status, String code, String diagnostics) =>
    Response(
      status,
      body: jsonEncode({
        'resourceType': 'OperationOutcome',
        'issue': [
          {
            'severity': 'error',
            'code': code,
            'diagnostics': diagnostics,
          }
        ],
      }),
      headers: {'Content-Type': 'application/fhir+json'},
    );
