import 'package:fhirant_server/src/utils/smart_scopes.dart';

/// The roles an account can hold.
const validRoles = {'admin', 'clinician', 'readonly'};

/// Why [rawScopes] is not a list of SMART scopes, or null when it is.
/// Shared by registration and the scope change (REVIEW-2026-09-17 A14).
String? scopesError(Object? rawScopes) {
  if (rawScopes is! List) return 'scopes must be an array of strings';
  for (final s in rawScopes) {
    if (s is! String || SmartScope.parse(s) == null) {
      return 'Invalid SMART scope: $s';
    }
  }
  return null;
}
