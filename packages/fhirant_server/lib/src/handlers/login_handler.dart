import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/auth/credential_check.dart';
import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:fhirant_server/src/utils/no_store.dart';
import 'package:fhirant_server/src/utils/smart_scopes.dart';
import 'package:shelf/shelf.dart';

export 'package:fhirant_server/src/auth/credential_check.dart'
    show lockoutDuration, maxFailedAttempts;

/// Handler for user login. Validates credentials and returns a JWT.
///
/// The patient context of the token comes from the ACCOUNT
/// (`users.patient_id`, set by an administrator), never from the request.
/// The body used to carry a `patient_id` the server copied into the token,
/// so any caller with patient/ scopes chose which patient's compartment it
/// was confined to (REVIEW-2026-09-06 finding 6).
Future<Response> loginHandler(
  Request request,
  FhirAntDb dbInterface,
  JwtService jwtService,
) async {
  try {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;

    // Validate required fields
    final username = body['username'];
    final password = body['password'];
    if (username is! String || password is! String) {
      return Response(
        400,
        body: jsonEncode({'error': 'Username and password are required'}),
      );
    }

    final User user;
    switch (await checkCredentials(dbInterface, username, password)) {
      case CredentialOk(user: final u):
        user = u;
      // One answer for a wrong password, an unknown account, a deactivated
      // one and a locked one. OWASP Authentication Cheat Sheet
      // ("Authentication Responses" and "Error Codes and URLs", raw
      // markdown read 2026-09-19): a generic message "regardless of
      // whether: The user ID or password was incorrect. The account does
      // not exist. The account is locked or disabled", and the same HTTP
      // code, since a differing code "may differ which can leak
      // information about whether the account is valid or not". This
      // answered 403 deactivated and 423 locked (REVIEW-2026-09-17 A12).
      // The lock still holds; the caller is not told of it.
      case CredentialInvalid():
      case CredentialInactive():
      case CredentialLocked():
        return Response(
          401,
          body: jsonEncode({'error': 'Invalid username or password'}),
        );
    }

    // Compute effective scopes: user-specific or role defaults
    final List<String> effectiveScopes;
    if (user.scopes != null && user.scopes!.isNotEmpty) {
      effectiveScopes =
          (jsonDecode(user.scopes!) as List<dynamic>).cast<String>();
    } else {
      effectiveScopes = SmartScopeEnforcer.defaultScopesForRole(user.role);
    }

    final patientId = user.patientId;

    // Generate JWT access token
    final token = jwtService.generateToken(
      userId: user.id,
      username: user.username,
      role: user.role,
      scopes: effectiveScopes,
      patientId: patientId,
      generation: user.tokenGeneration,
    );

    // Generate refresh token
    final refreshToken = jwtService.generateRefreshToken(
      userId: user.id,
      username: user.username,
      role: user.role,
      scopes: effectiveScopes,
      patientId: patientId,
      generation: user.tokenGeneration,
    );

    return Response.ok(
      jsonEncode({
        'token': token,
        'refresh_token': refreshToken,
        'token_type': 'Bearer',
        'username': user.username,
        'role': user.role,
        'scopes': effectiveScopes,
        if (patientId != null) 'patient': patientId,
      }),
      headers: jsonNoStoreHeaders,
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('Login failed', e, stackTrace);
    return Response.internalServerError(
      body: jsonEncode({'error': 'Login failed'}),
    );
  }
}

/// Admin-only handler to unlock a locked user account.
Future<Response> unlockAccountHandler(
  Request request,
  int userId,
  FhirAntDb dbInterface,
) async {
  try {
    // Require admin role
    final authUser = request.context['auth_user'] as Map<String, dynamic>?;
    if (authUser == null || authUser['role'] != 'admin') {
      return Response(
        403,
        body: jsonEncode({'error': 'Only administrators can unlock accounts'}),
      );
    }

    // Verify user exists
    final user = await dbInterface.getUserById(userId);
    if (user == null) {
      return Response(404, body: jsonEncode({'error': 'User not found'}));
    }

    await dbInterface.unlockAccount(userId);

    return Response.ok(
      jsonEncode({
        'message': 'Account unlocked successfully',
        'userId': userId,
        'username': user.username,
      }),
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('Unlock failed', e, stackTrace);
    return Response.internalServerError(
      body: jsonEncode({'error': 'Unlock failed'}),
    );
  }
}
