import 'dart:convert';

import 'package:shelf/shelf.dart';

/// Handler for `.well-known/smart-configuration`.
///
/// Returns the SMART on FHIR configuration document advertising
/// supported capabilities and endpoints.
Response smartConfigHandler(Request request) {
  final host = request.requestedUri.hasPort
      ? '${request.requestedUri.scheme}://${request.requestedUri.host}:${request.requestedUri.port}'
      : '${request.requestedUri.scheme}://${request.requestedUri.host}';

  final config = {
    'issuer': host,
    'authorization_endpoint': '$host/auth/authorize',
    'token_endpoint': '$host/auth/token',
    'revocation_endpoint': '$host/auth/revoke',
    'registration_endpoint': '$host/auth/register',
    'grant_types_supported': [
      'authorization_code',
      'refresh_token',
    ],
    'scopes_supported': [
      'openid',
      'fhirUser',
      'launch',
      'launch/patient',
      'system/*.*',
      'user/*.*',
      'user/*.rs',
      'user/*.cruds',
      'patient/*.*',
      'patient/*.rs',
    ],
    'response_types_supported': ['code'],
    'code_challenge_methods_supported': ['S256'],
    'token_endpoint_auth_methods_supported': ['none'],
    'capabilities': [
      'permission-v2',
      'launch-standalone',
      'authorize-post',
    ],
  };

  return Response.ok(
    jsonEncode(config),
    headers: {'Content-Type': 'application/json'},
  );
}
