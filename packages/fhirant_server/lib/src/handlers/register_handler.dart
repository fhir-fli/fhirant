import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';
import 'package:fhirant_server/src/utils/password_policy.dart';
import 'package:fhirant_server/src/utils/smart_scopes.dart';
import 'package:shelf/shelf.dart';

/// Valid user roles.
const _validRoles = {'admin', 'clinician', 'readonly'};

/// Handler for user registration.
///
/// First-user bootstrap: if no users exist, anyone can register and is forced
/// to admin role. Otherwise, only admins can register new users.
///
/// With [authenticationEnabled] false (Experimentation mode) registration is
/// refused outright: the endpoint is public, and with no users the first
/// registrant is forced to admin, so anyone on the network could register
/// the account Secure mode later trusts as its administrator
/// (REVIEW-2026-09-08 row 13). The operator provisions accounts through the
/// app (`AdminProvisioning`) or by starting the server with authentication.
Future<Response> registerHandler(
  Request request,
  FhirAntDb dbInterface,
  JwtService jwtService, {
  bool authenticationEnabled = true,
}) async {
  if (!authenticationEnabled) {
    return Response(
      403,
      body: jsonEncode({
        'error': 'Registration is disabled while authentication is off; '
            'accounts are provisioned by the operator.',
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }
  try {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;

    // Validate username
    final username = body['username'];
    if (username is! String || username.length < 3) {
      return Response(
        400,
        body: jsonEncode(
          {'error': 'Username must be a string of at least 3 characters'},
        ),
      );
    }

    // Validate password
    final password = body['password'];
    if (password is! String) {
      return Response(
        400,
        body: jsonEncode({'error': 'Password must be a string'}),
      );
    }
    final policyError = PasswordPolicy.validate(password);
    if (policyError != null) {
      return Response(400, body: jsonEncode({'error': policyError}));
    }

    // Validate role
    final requestedRole = body['role'] as String? ?? 'clinician';
    if (!_validRoles.contains(requestedRole)) {
      return Response(
        400,
        body: jsonEncode({
          'error': 'Invalid role. Must be one of: ${_validRoles.join(', ')}',
        }),
      );
    }

    final userCount = await dbInterface.getUserCount();

    // Determine the effective role
    String effectiveRole;
    if (userCount == 0) {
      // First-user bootstrap — force admin, no auth required
      effectiveRole = 'admin';
    } else {
      // Require admin auth
      final authUser = request.context['auth_user'] as Map<String, dynamic>?;
      if (authUser == null || authUser['role'] != 'admin') {
        return Response(
          403,
          body: jsonEncode(
            {'error': 'Only administrators can register new users'},
          ),
        );
      }
      effectiveRole = requestedRole;
    }

    // Optional: the Patient this account is about (`patient`, as
    // `Patient/[id]` or a bare id). Set here by the administrator, it is
    // what the server puts in the token's `patient` claim; a caller never
    // names its own patient context.
    String? patientId;
    final rawPatient = body['patient'];
    if (rawPatient != null) {
      if (rawPatient is! String) {
        return Response(
          400,
          body: jsonEncode({'error': 'patient must be a Patient reference'}),
        );
      }
      final id = rawPatient.startsWith('Patient/')
          ? rawPatient.substring('Patient/'.length)
          : rawPatient;
      // The FHIR id grammar (datatypes.html, id): [A-Za-z0-9\-\.]{1,64}.
      if (!RegExp(r'^[A-Za-z0-9\-\.]{1,64}$').hasMatch(id)) {
        return Response(
          400,
          body: jsonEncode({'error': 'patient is not a valid Patient id'}),
        );
      }
      patientId = id;
    }

    // Validate optional scopes
    final List<String> effectiveScopes;
    final rawScopes = body['scopes'];
    if (rawScopes != null) {
      if (rawScopes is! List) {
        return Response(
          400,
          body: jsonEncode({'error': 'scopes must be an array of strings'}),
        );
      }
      final scopeStrings = rawScopes.cast<String>();
      for (final s in scopeStrings) {
        if (SmartScope.parse(s) == null) {
          return Response(
            400,
            body: jsonEncode({'error': 'Invalid SMART scope: $s'}),
          );
        }
      }
      effectiveScopes = scopeStrings;
    } else {
      effectiveScopes = SmartScopeEnforcer.defaultScopesForRole(effectiveRole);
    }

    // Check for duplicate username
    final existing = await dbInterface.getUserByUsername(username);
    if (existing != null) {
      return Response(
        409,
        body: jsonEncode({'error': 'Username already exists'}),
      );
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
      patientId: patientId,
    );

    // Generate JWT tokens so the user is logged in immediately
    final token = jwtService.generateToken(
      userId: userId,
      username: username,
      role: effectiveRole,
      scopes: effectiveScopes,
      patientId: patientId,
    );
    final refreshToken = jwtService.generateRefreshToken(
      userId: userId,
      username: username,
      role: effectiveRole,
      scopes: effectiveScopes,
      patientId: patientId,
    );

    return Response(
      201,
      body: jsonEncode({
        'id': userId,
        'token': token,
        'refresh_token': refreshToken,
        'token_type': 'Bearer',
        'username': username,
        'role': effectiveRole,
        'scopes': effectiveScopes,
        if (patientId != null) 'patient': patientId,
      }),
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('Registration failed', e, stackTrace);
    return Response.internalServerError(
      body: jsonEncode({'error': 'Registration failed'}),
    );
  }
}
