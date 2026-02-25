/// SMART on FHIR scope parsing and enforcement.
///
/// Supports SMART v2 scope syntax: `context/resourceType.cruds`
/// where context is `user`, `patient`, or `system`.
class SmartScope {
  final String context;
  final String resourceType;
  final Set<String> permissions;

  SmartScope({
    required this.context,
    required this.resourceType,
    required this.permissions,
  });

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
        final segments =
            path.split('/').where((s) => s.isNotEmpty).toList();
        if (segments.length == 1 && !segments[0].startsWith('\$')) {
          return 's'; // GET /Patient → search
        }
        return 'r'; // GET /Patient/123 → read
      case 'POST':
        // POST to root = bundle/transaction, POST to type = create
        final segments =
            path.split('/').where((s) => s.isNotEmpty).toList();
        if (segments.length == 1 && !segments[0].startsWith('\$')) {
          return 'c'; // POST /Patient → create
        }
        // POST to $operations → read-level access
        if (path.contains('\$')) return 'r';
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

  /// Extracts the FHIR resource type from a URL path.
  ///
  /// Returns null for paths that don't target a specific resource type.
  static String? resourceTypeFromPath(String urlPath) {
    final path = urlPath.startsWith('/') ? urlPath.substring(1) : urlPath;
    if (path.isEmpty) return null;

    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;

    // Skip $-prefixed operations at root level
    if (segments[0].startsWith('\$')) return null;

    // Skip non-resource paths
    if (const {'auth', 'metadata', 'favicon.ico', '.well-known'}
        .contains(segments[0])) {
      return null;
    }

    // First segment is the resource type
    return segments[0];
  }
}
