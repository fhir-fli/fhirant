/// SMART on FHIR scope parsing and enforcement.
///
/// Supports SMART v2 scope syntax: `context/resourceType.cruds`
/// where context is `user`, `patient`, or `system`.
class SmartScope {
  SmartScope({
    required this.context,
    required this.resourceType,
    required this.permissions,
  });
  final String context;
  final String resourceType;
  final Set<String> permissions;

  /// Parses a SMART scope string like `user/Patient.cruds`.
  ///
  /// Returns null if the string is not a valid SMART scope.
  static SmartScope? parse(String scope) {
    final slash = scope.indexOf('/');
    if (slash < 1) return null;

    final context = scope.substring(0, slash);
    if (!const {'user', 'patient', 'system'}.contains(context)) return null;

    final rest = scope.substring(slash + 1);
    final dot = rest.indexOf('.');
    if (dot < 1 || dot == rest.length - 1) return null;

    final resourceType = rest.substring(0, dot);
    final permsStr = rest.substring(dot + 1);

    // Validate permission characters
    final validPerms = {'c', 'r', 'u', 'd', 's', '*'};
    final perms = <String>{};
    for (final ch in permsStr.split('')) {
      if (!validPerms.contains(ch)) return null;
      if (ch == '*') {
        perms.addAll(['c', 'r', 'u', 'd', 's']);
      } else {
        perms.add(ch);
      }
    }

    if (perms.isEmpty) return null;

    return SmartScope(
      context: context,
      resourceType: resourceType,
      permissions: perms,
    );
  }

  @override
  String toString() {
    final permsStr = permissions.contains('c') &&
            permissions.contains('r') &&
            permissions.contains('u') &&
            permissions.contains('d') &&
            permissions.contains('s')
        ? '*'
        : permissions.join();
    return '$context/$resourceType.$permsStr';
  }
}

/// Static methods for SMART scope enforcement.
class SmartScopeEnforcer {
  /// Returns the default scopes for a given role.
  static List<String> defaultScopesForRole(String role) {
    switch (role) {
      case 'admin':
        return ['system/*.*'];
      case 'clinician':
        return ['user/*.*'];
      case 'readonly':
        return ['user/*.rs'];
      default:
        return ['user/*.rs'];
    }
  }

  /// Checks whether the given scopes authorize the specified action.
  ///
  /// [scopes] - list of SMART scope strings
  /// [resourceType] - the FHIR resource type being accessed (e.g. "Patient")
  /// [permission] - single permission character: c, r, u, d, or s
  static bool isAuthorized(
    List<String> scopes,
    String resourceType,
    String permission,
  ) {
    for (final scopeStr in scopes) {
      final scope = SmartScope.parse(scopeStr);
      if (scope == null) continue;

      // Check resource type match (wildcard or exact)
      if (scope.resourceType != '*' && scope.resourceType != resourceType) {
        continue;
      }

      // Check permission
      if (scope.permissions.contains(permission)) {
        return true;
      }
    }
    return false;
  }

  /// Returns true if any of the scopes use the `patient/` context.
  static bool hasPatientScopes(List<String> scopes) {
    return scopes.any((s) {
      final parsed = SmartScope.parse(s);
      return parsed != null && parsed.context == 'patient';
    });
  }

  /// Returns true if the scopes are exclusively `patient/` context
  /// (no `user/` or `system/` scopes that would bypass patient filtering).
  static bool isPatientOnlyContext(List<String> scopes) {
    final parsed = scopes.map(SmartScope.parse).whereType<SmartScope>();
    if (parsed.isEmpty) return false;
    return parsed.every((s) => s.context == 'patient');
  }

  /// Root-level (`$`-prefixed) operations that read out or overwrite the
  /// entire data store, and therefore require system-level authorization.
  ///
  /// These have no resource type in the path, so the ordinary resource-type
  /// scope check does not apply to them — without this list they would be
  /// reachable by any authenticated user. Instance/type-scoped operations
  /// like `Patient/$export`, `<type>/$validate`, or `CodeSystem/$lookup`
  /// are NOT here: their first path segment is a resource type, so they are
  /// governed by the normal scope check.
  static const _privilegedSystemOperations = {
    r'$backup', // full database dump
    r'$restore', // full database overwrite
    r'$export', // system-level bulk dump
    r'$export-poll-status', // export job status/cancel
    r'$export-file', // export file download
  };

  /// Whether [urlPath] targets a privileged root-level system operation
  /// (see [_privilegedSystemOperations]).
  static bool isPrivilegedSystemOperation(String urlPath) {
    final path = urlPath.startsWith('/') ? urlPath.substring(1) : urlPath;
    final first =
        path.split('/').firstWhere((s) => s.isNotEmpty, orElse: () => '');
    return _privilegedSystemOperations.contains(first);
  }

  /// Whether the caller may invoke a privileged system operation: either the
  /// `admin` role, or possession of an explicit `system/` context scope.
  static bool isSystemAuthorized(List<String> scopes, String role) {
    if (role == 'admin') return true;
    return scopes.any((s) {
      final parsed = SmartScope.parse(s);
      return parsed != null && parsed.context == 'system';
    });
  }

  /// Maps an HTTP method + URL path to a SMART permission character.
  ///
  /// Returns null for paths that don't map to a FHIR permission
  /// (e.g. auth routes, metadata).
  static String? methodToPermission(String httpMethod, String urlPath) {
    // Normalize path
    final path = urlPath.startsWith('/') ? urlPath.substring(1) : urlPath;

    // Skip non-resource paths
    if (path.isEmpty ||
        path.startsWith('auth/') ||
        path == 'metadata' ||
        path == 'favicon.ico' ||
        path.startsWith('.well-known/')) {
      return null;
    }

    switch (httpMethod.toUpperCase()) {
      case 'GET':
        // Search (type-level GET) vs read (instance-level GET)
        final segments = path.split('/').where((s) => s.isNotEmpty).toList();
        if (segments.length == 1 && !segments[0].startsWith(r'$')) {
          return 's'; // GET /Patient → search
        }
        return 'r'; // GET /Patient/123 → read
      case 'POST':
        // POST to root = bundle/transaction, POST to type = create
        final segments = path.split('/').where((s) => s.isNotEmpty).toList();
        // `POST [base]/[type]/_search` and `POST [base]/_search` are the
        // search interaction (R4B http.html), not a create; this used to
        // demand `c`, so a read-only account could not search by POST.
        if (segments.isNotEmpty && segments.last == '_search') return 's';
        // `$meta-add` and `$meta-delete` write a new version of the resource
        // (R4 resource-operation-meta-add: "Add profiles, tags, and security
        // labels to a resource"); they used to pass as a read.
        if (segments.isNotEmpty &&
            (segments.last == r'$meta-add' ||
                segments.last == r'$meta-delete')) {
          return 'u';
        }
        if (segments.length == 1 && !segments[0].startsWith(r'$')) {
          return 'c'; // POST /Patient → create
        }
        // POST to $operations → read-level access
        if (path.contains(r'$')) return 'r';
        // POST / (bundle) → requires create
        if (path == '' || segments.isEmpty) return 'c';
        return 'c';
      case 'PUT':
        return 'u';
      case 'PATCH':
        return 'u';
      case 'DELETE':
        return 'd';
      default:
        return null;
    }
  }

  /// Root-level operations that touch no stored data — they work only on what
  /// the caller posted. Any authenticated caller may use these.
  ///
  /// This is an allowlist on purpose. Anything not named here is treated as
  /// data-reading, so a new operation added later fails closed rather than
  /// inheriting the old behaviour of no check at all.
  ///
  /// The operations it deliberately leaves out, each checked by reading the
  /// handler: `$fhirpath` fetches any resource by type and id, `$cql` loads
  /// patient data for evaluation, and both `$immds-forecast` variants read the
  /// patient and search immunizations.
  static const _rootNoDataOperations = {
    r'$validate',
    r'$transform',
  };

  /// The first path segment, with any leading slash removed.
  static String _firstSegment(String urlPath) {
    final path = urlPath.startsWith('/') ? urlPath.substring(1) : urlPath;
    return path.split('/').firstWhere((s) => s.isNotEmpty, orElse: () => '');
  }

  /// Whether [urlPath] is a root-level `$operation`.
  static bool isRootOperation(String urlPath) =>
      _firstSegment(urlPath).startsWith(r'$');

  /// Whether [urlPath] is a root-level operation that reads stored data.
  ///
  /// Deny-by-default: a root operation that is not on the no-data allowlist
  /// counts as data-reading.
  static bool isRootDataOperation(String urlPath) {
    final first = _firstSegment(urlPath);
    if (!first.startsWith(r'$')) return false;
    if (_privilegedSystemOperations.contains(first)) return false;
    return !_rootNoDataOperations.contains(first);
  }

  /// Whether [scopes] permit reading data the caller has not named.
  ///
  /// A root data operation can return anything in the database and the
  /// handlers behind them apply no compartment filter, so this requires a
  /// scope broad enough to cover that: a non-patient context (`user`/`system`)
  /// with the `*` resource wildcard and the needed permission.
  ///
  /// A `patient/` context is refused outright rather than allowed through,
  /// because nothing downstream would confine the result to that patient.
  static bool isUnscopedDataAccessAuthorized(
    List<String> scopes,
    String permission,
  ) {
    for (final scopeStr in scopes) {
      final scope = SmartScope.parse(scopeStr);
      if (scope == null) continue;
      if (scope.context == 'patient') continue;
      if (scope.resourceType != '*') continue;
      if (scope.permissions.contains(permission)) return true;
    }
    return false;
  }

  /// The SMART scopes that are not resource permissions: launch-context
  /// requests and OpenID Connect scopes. SMART App Launch STU2
  /// (conformance.html, read whole 2026-09-07) names `openid`
  /// (sso-openid-connect), `launch`, `launch/patient`, `launch/encounter`,
  /// `offline_access` and `online_access`; `fhirUser` and `profile` are the
  /// OpenID Connect identity scopes of the same guide. They say what an app
  /// wants around the data, never what it may do with it, so the enforcer
  /// ignores them; they used to fail [allScopesParse] and lock every standard
  /// SMART app out.
  static const nonResourceScopes = <String>{
    'openid',
    'fhirUser',
    'profile',
    'launch',
    'launch/patient',
    'launch/encounter',
    'offline_access',
    'online_access',
  };

  /// [scopes] without the entries of [nonResourceScopes].
  static List<String> resourceScopesOf(Iterable<String> scopes) =>
      scopes.where((s) => !nonResourceScopes.contains(s)).toList();

  /// Contexts ordered by breadth: a grant at a broader context covers a
  /// request at a narrower one, never the reverse.
  static const _contextRank = {'patient': 0, 'user': 1, 'system': 2};

  /// The scopes an account actually receives when it asks for [requested]
  /// and holds [granted]: for each requested resource scope, the permissions
  /// it shares with a granted scope of the same or a broader context on the
  /// same (or wildcard) resource type. A request nothing covers is dropped.
  ///
  /// SMART App Launch STU2 app-launch.html, token response `scope`: "Scope
  /// of access authorized. Note that this can be different from the scopes
  /// requested by the app." Before this the requested string was issued
  /// verbatim, so a readonly account could ask for `system/*.*` and get it
  /// (REVIEW-2026-09-06 finding 1).
  ///
  /// With [patientContext] false the account has no Patient to confine a
  /// `patient/` scope to, so such requests are dropped rather than issued
  /// unenforceable. Non-resource scopes are carried through unchanged. An
  /// empty [requested] means "what I have" and returns [granted].
  static List<String> grantScopes(
    List<String> requested,
    List<String> granted, {
    bool patientContext = true,
  }) {
    if (requested.isEmpty) return List.of(granted);
    final held = granted.map(SmartScope.parse).whereType<SmartScope>().toList();
    final out = <String>[];
    for (final wanted in requested) {
      if (nonResourceScopes.contains(wanted)) {
        if (!out.contains(wanted)) out.add(wanted);
        continue;
      }
      final r = SmartScope.parse(wanted);
      if (r == null) continue;
      if (r.context == 'patient' && !patientContext) continue;
      final permissions = <String>{};
      for (final g in held) {
        if (_contextRank[g.context]! < _contextRank[r.context]!) continue;
        if (g.resourceType != '*' && g.resourceType != r.resourceType) {
          continue;
        }
        permissions.addAll(r.permissions.intersection(g.permissions));
      }
      if (permissions.isEmpty) continue;
      final letters = ['c', 'r', 'u', 'd', 's'].where(permissions.contains);
      final suffix = permissions.length == 5 ? '*' : letters.join();
      final scope = '${r.context}/${r.resourceType}.$suffix';
      if (!out.contains(scope)) out.add(scope);
    }
    return out;
  }

  /// Whether every entry in [scopes] is a scope this server understands.
  ///
  /// Callers must reject the request when this is false rather than skipping
  /// the offending entry: an unparsed scope may be the one that NARROWS
  /// access, and dropping it silently widens what the token can do.
  static bool allScopesParse(List<String> scopes) =>
      scopes.every((s) => SmartScope.parse(s) != null);

  /// Extracts the FHIR resource type from a URL path.
  ///
  /// Returns null for paths that don't target a specific resource type.
  static String? resourceTypeFromPath(String urlPath) {
    final path = urlPath.startsWith('/') ? urlPath.substring(1) : urlPath;
    if (path.isEmpty) return null;

    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;

    // Skip $-prefixed operations at root level
    if (segments[0].startsWith(r'$')) return null;

    // Skip non-resource paths
    if (const {'auth', 'metadata', 'favicon.ico', '.well-known'}
        .contains(segments[0])) {
      return null;
    }

    // First segment is the resource type
    return segments[0];
  }
}
