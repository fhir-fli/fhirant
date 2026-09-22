import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/auth/account_rules.dart';
import 'package:fhirant_server/src/auth/bootstrap.dart';
import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:fhirant_server/src/utils/no_store.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';
import 'package:fhirant_server/src/utils/password_policy.dart';
import 'package:fhirant_server/src/utils/smart_scopes.dart';
import 'package:shelf/shelf.dart';

/// Valid user roles.
// The one list, shared with the role change (account_rules.dart).
const Set<String> _validRoles = validRoles;

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
///
/// With a [bootstrapToken] (the CLI issues one at start when the store has
/// no account; `auth/bootstrap.dart`) the first registration must present
/// it, in the `X-Bootstrap-Token` header or the `bootstrap_token` body
/// field. Without it, the first `POST /auth/register` from anyone on the
/// network became the administrator (REVIEW-2026-09-17 A15). The app passes
/// none: it provisions its administrator locally before serving.
Future<Response> registerHandler(
  Request request,
  FhirAntDb dbInterface,
  JwtService jwtService, {
  bool authenticationEnabled = true,
  String? bootstrapToken,
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
  // The body is parsed outside the block below: a garbled body is the
  // client's 400 (RFC 9110 §15.5.1, "malformed request syntax"), and the
  // one catch used to answer it as 500 "Registration failed"
  // (every_route_refuses_a_garbled_body_test.dart, 2026-09-22).
  final Object? decoded;
  try {
    decoded = jsonDecode(await request.readAsString());
  } on FormatException catch (e) {
    return Response(
      400,
      body: jsonEncode({'error': 'Body is not JSON: ${e.message}'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
  if (decoded is! Map<String, dynamic>) {
    return Response(
      400,
      body: jsonEncode({'error': 'Body must be a JSON object'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
  final body = decoded;
  try {
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
      // First-user bootstrap — force admin; no account can authenticate
      // yet, so the proof is the bootstrap token when the server has one.
      if (bootstrapToken != null) {
        final presented = request.headers[bootstrapTokenHeader] ??
            body['bootstrap_token'] as String?;
        if (presented == null ||
            !bootstrapTokenMatches(presented, bootstrapToken)) {
          return Response(
            403,
            body: jsonEncode({
              'error': 'The first registration must carry the bootstrap '
                  'token the server printed at start '
                  '(header X-Bootstrap-Token or body bootstrap_token)',
            }),
          );
        }
      }
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
    final hash = await PasswordHasher.hashPassword(password, salt);

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
      headers: jsonNoStoreHeaders,
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('Registration failed', e, stackTrace);
    return Response.internalServerError(
      body: jsonEncode({'error': 'Registration failed'}),
    );
  }
}
