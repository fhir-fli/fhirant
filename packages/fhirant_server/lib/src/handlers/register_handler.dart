import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';
import 'package:fhirant_server/src/utils/smart_scopes.dart';
import 'package:shelf/shelf.dart';

/// Valid user roles.
const _validRoles = {'admin', 'clinician', 'readonly'};

/// Handler for user registration.
///
/// First-user bootstrap: if no users exist, anyone can register and is forced
/// to admin role. Otherwise, only admins can register new users.
Future<Response> registerHandler(Request request, FhirAntDb dbInterface) async {
  try {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;

    // Validate username
    final username = body['username'];
    if (username is! String || username.length < 3) {
      return Response(400,
          body: jsonEncode({
            'error': 'Username must be a string of at least 3 characters'
          }));
    }

    // Validate password
    final password = body['password'];
    if (password is! String || password.length < 8) {
      return Response(400,
          body: jsonEncode({
            'error': 'Password must be a string of at least 8 characters'
          }));
    }

    // Validate role
    final requestedRole = body['role'] as String? ?? 'clinician';
    if (!_validRoles.contains(requestedRole)) {
      return Response(400,
          body: jsonEncode(
              {'error': 'Invalid role. Must be one of: ${_validRoles.join(', ')}'}));
    }

    final userCount = await dbInterface.getUserCount();

    // Determine the effective role
    String effectiveRole;
    if (userCount == 0) {
      // First-user bootstrap — force admin, no auth required
      effectiveRole = 'admin';
    } else {
      // Require admin auth
      final authUser =
          request.context['auth_user'] as Map<String, dynamic>?;
      if (authUser == null || authUser['role'] != 'admin') {
        return Response(403,
            body: jsonEncode(
                {'error': 'Only administrators can register new users'}));
      }
      effectiveRole = requestedRole;
    }

    // Validate optional scopes
    final List<String> effectiveScopes;
    final rawScopes = body['scopes'];
    if (rawScopes != null) {
      if (rawScopes is! List) {
        return Response(400,
            body: jsonEncode({'error': 'scopes must be an array of strings'}));
      }
      final scopeStrings = rawScopes.cast<String>() as List<String>;
      for (final s in scopeStrings) {
        if (SmartScope.parse(s) == null) {
          return Response(400,
              body: jsonEncode({'error': 'Invalid SMART scope: $s'}));
        }
      }
      effectiveScopes = scopeStrings;
    } else {
      effectiveScopes = SmartScopeEnforcer.defaultScopesForRole(effectiveRole);
    }

    // Check for duplicate username
    final existing = await dbInterface.getUserByUsername(username);
    if (existing != null) {
      return Response(409,
          body: jsonEncode({'error': 'Username already exists'}));
    }

    // Hash password and create user
    final salt = PasswordHasher.generateSalt();
    final hash = PasswordHasher.hashPassword(password, salt);

    final userId = await dbInterface.createUser(
      username: username,
      passwordHash: hash,
      salt: salt,
      role: effectiveRole,
      scopes: jsonEncode(effectiveScopes),
    );

    return Response(201,
        body: jsonEncode({
          'id': userId,
          'username': username,
          'role': effectiveRole,
          'scopes': effectiveScopes,
        }));
  } catch (e) {
    return Response.internalServerError(
        body: jsonEncode({'error': 'Registration failed: $e'}));
  }
}
