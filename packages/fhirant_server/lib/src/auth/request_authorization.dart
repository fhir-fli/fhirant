import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
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

  // A patient-context scope with no patient context has nothing to be
  // confined to: refused before anything else, at the root as at a type.
  // It used to be refused only on a typed path, so `GET /?_type=Patient`
  // returned every patient (REVIEW-2026-09-17 A1).
  if (SmartScopeEnforcer.hasPatientScopes(scopes) &&
      principal.patientId == null) {
    return forbidden(
      'patient/ scopes require a patient context (patient claim in JWT)',
    );
  }

  final permission = SmartScopeEnforcer.methodToPermission(method, path);
  final resourceType = SmartScopeEnforcer.resourceTypeFromPath(path);

  // The audit trail records what every caller did; nobody it records may
  // write it. Every write of an AuditEvent by a client (create, update,
  // patch, delete, `$meta-add`, `$meta-delete`, conditional or not, REST
  // or Bundle entry) is refused, the administrator's included: the server
  // writes its own records straight to the store (REVIEW-2026-09-17 A2).
  if (resourceType == 'AuditEvent' &&
      permission != null &&
      permission != 'r' &&
      permission != 's') {
    return forbidden(
      'AuditEvent is written by this server alone; it cannot be created, '
      'changed or deleted by a client.',
    );
  }

  // Deleting a SearchParameter stops the indexing it defined, for every
  // later write of its base types: system authority, as creating one is
  // (storeRefusal). Decided here so the conditional delete and a Bundle
  // entry answer as the instance delete does; the check used to live in
  // the instance delete handler alone (REVIEW-2026-09-17 A6).
  if (resourceType == 'SearchParameter' &&
      permission == 'd' &&
      !principal.isSystem) {
    return forbidden(
      'A SearchParameter changes what this server indexes; deleting one '
      'requires system-level (admin) privilege.',
    );
  }

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
    // Only enforce scopes for resource-targeted requests. `_history` and
    // `_search` at the root name no type; their handlers check each type
    // they touch.
    if (resourceType != null &&
        resourceType != '_history' &&
        resourceType != '_search') {
      if (!principal.may(resourceType, permission)) {
        return forbidden('Insufficient scope for $permission on $resourceType');
      }
    }
  }
  return null;
}

/// Why [principal] may not store [resource], or null. A `Subscription` with
/// a rest-hook channel makes this server PUT every matching resource to a
/// URL of the subscriber's choosing, with headers of the subscriber's
/// choosing, from inside the network, on every write: an outbound feed of
/// the record. Creating or changing one is system authority (the admin
/// role or a `system/` scope); a websocket subscription, which the client
/// dials in for, stays open to anyone who may create Subscriptions. Any
/// account with `c` on Subscription could register a rest-hook
/// (REVIEW-2026-09-08 row 18).
Response? storeRefusal(Principal? principal, fhir.Resource resource) {
  if (principal == null) return null;
  // A SearchParameter changes what this server indexes on every write of
  // its base types, and its expression runs inside every one of those
  // saves; the Azure FHIR service and HAPI treat defining one as an
  // administrator's act. System authority, like a rest-hook Subscription.
  if (resource is fhir.SearchParameter && !principal.isSystem) {
    return forbidden(
      'A SearchParameter changes what this server indexes; creating or '
      'changing one requires system-level (admin) privilege.',
    );
  }
  if (resource is! fhir.Subscription) return null;
  final channel = resource.channel.type.valueString;
  if (channel == 'rest-hook' && !principal.isSystem) {
    return forbidden(
      'A rest-hook Subscription sends resources out of this server; creating '
      'or changing one requires system-level (admin) privilege.',
    );
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
