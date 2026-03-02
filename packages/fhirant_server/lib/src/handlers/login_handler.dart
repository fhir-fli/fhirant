import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';
import 'package:fhirant_server/src/utils/smart_scopes.dart';
import 'package:shelf/shelf.dart';

/// Handler for user login. Validates credentials and returns a JWT.
Future<Response> loginHandler(
    Request request, FhirAntDb dbInterface, JwtService jwtService) async {
  try {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;

    // Validate required fields
    final username = body['username'];
    final password = body['password'];
    if (username is! String || password is! String) {
      return Response(400,
          body:
              jsonEncode({'error': 'Username and password are required'}));
    }

    // Look up user
    final user = await dbInterface.getUserByUsername(username);
    if (user == null) {
      return Response(401,
          body: jsonEncode({'error': 'Invalid username or password'}));
    }

    // Check if account is active
    if (!user.active) {
      return Response(403,
          body: jsonEncode({'error': 'Account is deactivated'}));
    }

    // Verify password
    if (!PasswordHasher.verifyPassword(
        password, user.salt, user.passwordHash)) {
      return Response(401,
          body: jsonEncode({'error': 'Invalid username or password'}));
    }

    // Update last login
    await dbInterface.updateLastLogin(user.id);

    // Compute effective scopes: user-specific or role defaults
    final List<String> effectiveScopes;
    if (user.scopes != null && user.scopes!.isNotEmpty) {
      effectiveScopes =
          (jsonDecode(user.scopes!) as List<dynamic>).cast<String>();
    } else {
      effectiveScopes = SmartScopeEnforcer.defaultScopesForRole(user.role);
    }

    // Check for optional patient context (for patient-facing apps)
    final patientId = body['patient_id'] as String?;

    // Generate JWT access token
    final token = jwtService.generateToken(
      userId: user.id,
      username: user.username,
      role: user.role,
      scopes: effectiveScopes,
      patientId: patientId,
    );

    // Generate refresh token
    final refreshToken = jwtService.generateRefreshToken(
      userId: user.id,
      username: user.username,
      role: user.role,
      scopes: effectiveScopes,
      patientId: patientId,
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
    );
  } catch (e) {
    return Response.internalServerError(
        body: jsonEncode({'error': 'Login failed: $e'}));
  }
}
