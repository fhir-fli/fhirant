import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/auth/account_rules.dart';
import 'package:fhirant_server/src/auth/credential_check.dart';
import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:fhirant_server/src/utils/no_store.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';
import 'package:fhirant_server/src/utils/password_policy.dart';
import 'package:fhirant_server/src/utils/smart_scopes.dart';
import 'package:shelf/shelf.dart';

/// Account management (REVIEW-2026-09-17 A14). Until this, no route changed
/// a password, deactivated an account, or changed a role or scopes: a
/// leaked password could only be fixed in the database.
///
/// Every change here that alters what the account can do — its password,
/// role, scopes or activation — also moves the account's token generation
/// on (`FhirAntDb.bumpTokenGeneration`), so every token issued before the
/// change stops working on its next use (OWASP Session Management Cheat
/// Sheet, "Renew the Session ID After Any Privilege Level Change";
/// `auth/token_bound.dart`). The password change answers with a fresh
/// token pair for the caller, as login does.
///
/// The admin routes require the admin role, as `/admin/unlock` does. The
/// administrator's own account can be changed by another administrator;
/// an administrator cannot deactivate or demote the last active
/// administrator, which would leave the server with nobody to run it.

/// `POST /auth/password`: the caller changes its own password. Body:
/// `current_password`, `new_password`. The current password is checked
/// through the one credential check (it counts failures and locks like a
/// login); the new one must meet the password policy.
Future<Response> changePasswordHandler(
  Request request,
  FhirAntDb dbInterface,
  JwtService jwtService,
) async {
  try {
    final authUser = request.context['auth_user'] as Map<String, dynamic>?;
    if (authUser == null) {
      return _json(401, {'error': 'Authentication required'});
    }
    final body = await _body(request);
    if (body == null) return _json(400, {'error': 'Invalid JSON body'});
    final current = body['current_password'];
    final next = body['new_password'];
    if (current is! String || next is! String) {
      return _json(
        400,
        {'error': 'current_password and new_password are required'},
      );
    }
    final policyError = PasswordPolicy.validate(next);
    if (policyError != null) return _json(400, {'error': policyError});

    final username = authUser['username'] as String? ?? '';
    final User user;
    switch (await checkCredentials(dbInterface, username, current)) {
      case CredentialOk(user: final u):
        user = u;
      case CredentialInvalid():
      case CredentialInactive():
      case CredentialLocked():
        // The same answer as a login, for the same reason (A12).
        return _json(401, {'error': 'Invalid username or password'});
    }

    await _setPassword(dbInterface, user.id, next);
    FhirantLogging().logInfo('Password changed for user ${user.id}');
    return Response.ok(
      jsonEncode(_tokenPair(jwtService, await _fresh(dbInterface, user.id))),
      headers: jsonNoStoreHeaders,
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('Password change failed', e, stackTrace);
    return _json(500, {'error': 'Password change failed'});
  }
}

/// `GET /admin/users`: every account, without its secrets.
Future<Response> listUsersHandler(
  Request request,
  FhirAntDb dbInterface,
) async {
  final refused = _requireAdmin(request);
  if (refused != null) return refused;
  final users = await dbInterface.getAllUsers();
  return Response.ok(
    jsonEncode({
      'users': [for (final u in users) _publicUser(u)],
    }),
  );
}

/// `POST /admin/users/<id>/password`: an administrator sets a new
/// password for the account. Body: `new_password`.
Future<Response> resetPasswordHandler(
  Request request,
  int userId,
  FhirAntDb dbInterface,
) async {
  final refused = _requireAdmin(request);
  if (refused != null) return refused;
  final user = await dbInterface.getUserById(userId);
  if (user == null) return _json(404, {'error': 'User not found'});
  final body = await _body(request);
  final next = body?['new_password'];
  if (next is! String) {
    return _json(400, {'error': 'new_password is required'});
  }
  final policyError = PasswordPolicy.validate(next);
  if (policyError != null) return _json(400, {'error': policyError});
  await _setPassword(dbInterface, userId, next);
  FhirantLogging().logInfo('Password reset for user $userId by admin');
  return Response.ok(
    jsonEncode({'message': 'Password reset', ..._publicUser(user)}),
  );
}

/// `POST /admin/users/<id>/activate` and `/deactivate`.
Future<Response> setActiveHandler(
  Request request,
  int userId,
  FhirAntDb dbInterface, {
  required bool active,
}) async {
  final refused = _requireAdmin(request);
  if (refused != null) return refused;
  final user = await dbInterface.getUserById(userId);
  if (user == null) return _json(404, {'error': 'User not found'});
  if (!active) {
    final last = await _lastActiveAdmin(dbInterface, user);
    if (last != null) return last;
    await dbInterface.deactivateUser(userId);
  } else {
    await dbInterface.activateUser(userId);
  }
  await dbInterface.bumpTokenGeneration(userId);
  final updated = await _fresh(dbInterface, userId);
  FhirantLogging().logInfo(
    'User $userId ${active ? 'activated' : 'deactivated'} by admin',
  );
  return Response.ok(jsonEncode(_publicUser(updated)));
}

/// `PUT /admin/users/<id>/role`. Body: `role`, one of [validRoles].
Future<Response> setRoleHandler(
  Request request,
  int userId,
  FhirAntDb dbInterface,
) async {
  final refused = _requireAdmin(request);
  if (refused != null) return refused;
  final user = await dbInterface.getUserById(userId);
  if (user == null) return _json(404, {'error': 'User not found'});
  final body = await _body(request);
  final role = body?['role'];
  if (role is! String || !validRoles.contains(role)) {
    return _json(
      400,
      {'error': 'Invalid role. Must be one of: ${validRoles.join(', ')}'},
    );
  }
  if (role != 'admin') {
    final last = await _lastActiveAdmin(dbInterface, user);
    if (last != null) return last;
  }
  await dbInterface.updateUserRole(userId, role);
  await dbInterface.bumpTokenGeneration(userId);
  FhirantLogging().logInfo('Role of user $userId set to $role by admin');
  return Response.ok(
    jsonEncode(_publicUser(await _fresh(dbInterface, userId))),
  );
}

/// `PUT /admin/users/<id>/scopes`. Body: `scopes`, an array of SMART
/// scopes, or null for the role's defaults.
Future<Response> setScopesHandler(
  Request request,
  int userId,
  FhirAntDb dbInterface,
) async {
  final refused = _requireAdmin(request);
  if (refused != null) return refused;
  final user = await dbInterface.getUserById(userId);
  if (user == null) return _json(404, {'error': 'User not found'});
  final body = await _body(request);
  if (body == null || !body.containsKey('scopes')) {
    return _json(400, {'error': 'scopes is required (an array, or null)'});
  }
  final raw = body['scopes'];
  if (raw != null) {
    final error = scopesError(raw);
    if (error != null) return _json(400, {'error': error});
  }
  await dbInterface.updateUserScopes(
    userId,
    raw == null ? null : jsonEncode((raw as List).cast<String>()),
  );
  await dbInterface.bumpTokenGeneration(userId);
  FhirantLogging().logInfo('Scopes of user $userId changed by admin');
  return Response.ok(
    jsonEncode(_publicUser(await _fresh(dbInterface, userId))),
  );
}

Response? _requireAdmin(Request request) {
  final authUser = request.context['auth_user'] as Map<String, dynamic>?;
  if (authUser == null || authUser['role'] != 'admin') {
    return _json(403, {'error': 'Only administrators can manage accounts'});
  }
  return null;
}

/// Refuses when [user] is the last active administrator: deactivating or
/// demoting it would leave nobody who can manage the server.
Future<Response?> _lastActiveAdmin(FhirAntDb dbInterface, User user) async {
  if (user.role != 'admin' || !user.active) return null;
  final admins = (await dbInterface.getAllUsers())
      .where((u) => u.role == 'admin' && u.active)
      .length;
  if (admins > 1) return null;
  return _json(
    409,
    {'error': 'This is the last active administrator; add another first'},
  );
}

Future<void> _setPassword(FhirAntDb db, int userId, String password) async {
  final salt = PasswordHasher.generateSalt();
  await db.updatePassword(
    userId,
    await PasswordHasher.hashPassword(password, salt),
    salt,
  );
  await db.bumpTokenGeneration(userId);
}

Future<User> _fresh(FhirAntDb db, int userId) async =>
    (await db.getUserById(userId))!;

Map<String, dynamic> _publicUser(User u) => {
      'id': u.id,
      'username': u.username,
      'role': u.role,
      'active': u.active,
      'scopes': u.scopes == null
          ? SmartScopeEnforcer.defaultScopesForRole(u.role)
          : jsonDecode(u.scopes!),
      if (u.patientId != null) 'patient': u.patientId,
      'locked': u.lockedUntil != null && u.lockedUntil!.isAfter(DateTime.now()),
      if (u.lastLogin != null) 'last_login': u.lastLogin!.toIso8601String(),
    };

/// A fresh token pair for [user], as login issues it.
Map<String, dynamic> _tokenPair(JwtService jwtService, User user) {
  final scopes = user.scopes != null && user.scopes!.isNotEmpty
      ? (jsonDecode(user.scopes!) as List<dynamic>).cast<String>()
      : SmartScopeEnforcer.defaultScopesForRole(user.role);
  return {
    'token': jwtService.generateToken(
      userId: user.id,
      username: user.username,
      role: user.role,
      scopes: scopes,
      patientId: user.patientId,
      generation: user.tokenGeneration,
    ),
    'refresh_token': jwtService.generateRefreshToken(
      userId: user.id,
      username: user.username,
      role: user.role,
      scopes: scopes,
      patientId: user.patientId,
      generation: user.tokenGeneration,
    ),
    'token_type': 'Bearer',
    'username': user.username,
    'role': user.role,
    'scopes': scopes,
    if (user.patientId != null) 'patient': user.patientId,
  };
}

Future<Map<String, dynamic>?> _body(Request request) async {
  try {
    final decoded = jsonDecode(await request.readAsString());
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

Response _json(int status, Map<String, dynamic> body) =>
    Response(status, body: jsonEncode(body));
