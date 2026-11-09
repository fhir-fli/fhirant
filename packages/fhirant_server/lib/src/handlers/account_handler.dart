import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/auth/account_rules.dart';
import 'package:fhirant_server/src/auth/credential_check.dart';
import 'package:fhirant_server/src/auth/owner_claim.dart';
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

/// `POST /admin/users/<id>/password`: an administrator resets the
/// account's password. No body (or an empty JSON object): the
/// administrator neither chooses the new password nor is handed one. The
/// old password and every session from before stop working, and the
/// account waits for its owner to set their own (`auth/owner_claim.dart`;
/// OWASP ASVS 5.0.0 V6.4.6).
Future<Response> resetPasswordHandler(
  Request request,
  int userId,
  FhirAntDb dbInterface,
) async {
  final refused = _requireAdmin(request);
  if (refused != null) return refused;
  final user = await dbInterface.getUserById(userId);
  if (user == null) return _json(404, {'error': 'User not found'});
  final raw = await request.readAsString();
  if (raw.trim().isNotEmpty) {
    final Object? body;
    try {
      body = jsonDecode(raw);
    } on FormatException {
      return _json(400, {'error': 'Body must be a JSON object, or empty'});
    }
    if (body is! Map<String, dynamic>) {
      return _json(400, {'error': 'Body must be a JSON object, or empty'});
    }
    if (body.isNotEmpty) {
      return _json(400, {
        'error': "An administrator does not choose a user's password. Send "
            'no body: the user sets their own with POST /auth/claim, and you '
            'approve it with the code they are shown.',
      });
    }
  }
  final none = await unusablePassword();
  await dbInterface.awaitOwner(
    userId,
    none.hash,
    none.salt,
    DateTime.now().add(ownerWaitLifetime),
  );
  await dbInterface.bumpTokenGeneration(userId);
  FhirantLogging().logInfo('Password reset for user $userId by admin');
  return Response.ok(
    jsonEncode({
      'message': 'Password reset',
      ..._publicUser(await _fresh(dbInterface, userId)),
    }),
  );
}

/// `POST /auth/claim`: the owner of an account waiting for them sets their
/// own password, from their own device. Body: `username`, `new_password`
/// (held to the password policy). The reply carries a code for the owner
/// to show the administrator, who approves with it
/// (`POST /admin/users/<id>/approve`; `auth/owner_claim.dart`).
///
/// The reply is the same whether or not the account exists and waits: a
/// different answer would tell anyone which accounts were just reset. For
/// an account that does not wait, the code is never stored and approves
/// nothing. The password is hashed either way, so the time taken does not
/// tell them apart. Rate-limited with the credential endpoints, and
/// recorded in the audit trail with the name sent.
Future<Response> claimHandler(Request request, FhirAntDb dbInterface) async {
  try {
    final body = await _body(request);
    final username = body?['username'];
    final next = body?['new_password'];
    if (username is! String || next is! String) {
      return _json(400, {'error': 'username and new_password are required'});
    }
    final tried = {'attempted_username': username};
    final policyError = PasswordPolicy.validate(next);
    if (policyError != null) {
      return _json(400, {'error': policyError}).change(context: tried);
    }
    final salt = PasswordHasher.generateSalt();
    final hash = await PasswordHasher.hashPassword(next, salt);
    final code = newClaimCode();
    await dbInterface.holdClaim(
      username,
      hash,
      salt,
      canonicalClaimCode(code)!,
    );
    return Response(
      202,
      body: jsonEncode({
        'code': code,
        'message': 'Show this code to your administrator. Your password '
            'works once they approve it with the code. Sending a password '
            'again replaces this one and gives a new code.',
      }),
      headers: jsonNoStoreHeaders,
      context: tried,
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('Password claim failed', e, stackTrace);
    return _json(500, {'error': 'Password claim failed'});
  }
}

/// `POST /admin/users/<id>/approve`: an administrator approves the
/// password the account's owner sent, with the code the owner was shown.
/// Body: `code` (dashes and case optional, RFC 8628 §6.1). A wrong code
/// drops the password the owner sent; they send it again for a new code.
Future<Response> approveClaimHandler(
  Request request,
  int userId,
  FhirAntDb dbInterface,
) async {
  final refused = _requireAdmin(request);
  if (refused != null) return refused;
  final body = await _body(request);
  final raw = body?['code'];
  if (raw is! String) return _json(400, {'error': 'code is required'});
  final code = canonicalClaimCode(raw);
  // Not a code at all is a typing slip: what the owner sent stays.
  if (code == null) return _json(400, {'error': 'That is not a code'});
  switch (await dbInterface.approveClaim(userId, code)) {
    case ClaimApproval.approved:
      await dbInterface.bumpTokenGeneration(userId);
      FhirantLogging().logInfo('Password of user $userId approved by admin');
      return Response.ok(
        jsonEncode(_publicUser(await _fresh(dbInterface, userId))),
      );
    case ClaimApproval.noAccount:
      return _json(404, {'error': 'User not found'});
    case ClaimApproval.notAwaiting:
      return _json(409, {
        'error': 'This account is not waiting for a password',
      });
    case ClaimApproval.expired:
      return _json(409, {
        'error': 'The wait for this account ran out; reset its password again',
      });
    case ClaimApproval.nothingSent:
      return _json(409, {
        'error': 'The owner has not sent a password yet (POST /auth/claim)',
      });
    case ClaimApproval.wrongCode:
      return _json(400, {
        'error': 'The code does not match. The password the owner sent was '
            'dropped; they send it again for a new code.',
      });
  }
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
    if (!await dbInterface.deactivateUnlessLastAdmin(userId)) {
      return _lastActiveAdmin;
    }
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
  if (!await dbInterface.setRoleUnlessLastAdmin(userId, role)) {
    return _lastActiveAdmin;
  }
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

/// The refusal when the account is the last active administrator:
/// deactivating or demoting it would leave nobody who can manage the
/// server. The store checks and changes in one statement
/// (`setRoleUnlessLastAdmin`, `deactivateUnlessLastAdmin`); the count and
/// the change were separate, and two admins demoting each other at once
/// left none (REVIEW-2026-10-17, ASVS 5.0.0 V15.4.2).
Response get _lastActiveAdmin => _json(
      409,
      {'error': 'This is the last active administrator; add another first'},
    );

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
      'scopes': SmartScopeEnforcer.heldScopes(u),
      if (u.patientId != null) 'patient': u.patientId,
      'locked': u.lockedUntil != null && u.lockedUntil!.isAfter(DateTime.now()),
      if (u.awaitingOwnerUntil != null)
        'awaiting_owner_until': u.awaitingOwnerUntil!.toUtc().toIso8601String(),
      if (u.awaitingOwnerUntil != null) 'password_sent': u.claimSent,
      if (u.lastLogin != null) 'last_login': u.lastLogin!.toIso8601String(),
    };

/// A fresh token pair for [user], as login issues it.
Map<String, dynamic> _tokenPair(JwtService jwtService, User user) {
  final scopes = SmartScopeEnforcer.heldScopes(user);
  final session = jwtService.issueSession(user, scopes: scopes);
  return {
    'token': session.access,
    'refresh_token': session.refresh,
    'token_type': 'Bearer',
    'username': user.username,
    'role': user.role,
    'scopes': scopes,
    if (user.patientId != null) 'patient': user.patientId,
  };
}

/// The JSON object in the body, or null when the body is not one (the
/// caller's 400). Only a parse failure is null; this used to swallow
/// every failure.
Future<Map<String, dynamic>?> _body(Request request) async {
  try {
    final decoded = jsonDecode(await request.readAsString());
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}

Response _json(int status, Map<String, dynamic> body) =>
    Response(status, body: jsonEncode(body));
