import 'dart:convert';

import 'package:shelf/shelf.dart';

/// Handler for `.well-known/smart-configuration`.
///
/// SMART App Launch STU2 conformance.html, read whole 2026-09-07. Every key
/// here is one that page defines, with the value this server can stand
/// behind:
/// - `issuer` is "Required if the server's capabilities include
///   sso-openid-connect; otherwise, omitted." This server issues no
///   id_token, so no `issuer`, and no `openid`/`fhirUser` in the scopes.
/// - `scopes_supported`: "The server SHALL support all scopes listed here".
/// - `code_challenge_methods_supported`: "The S256 method SHALL be included
///   in this list, and the plain method SHALL NOT be included".
/// - `capabilities`: from the page's list. `permission-offline`: refresh
///   tokens are issued with every grant. `context-standalone-patient`: the
///   `patient` token parameter comes from the account's linked Patient.
Response smartConfigHandler(Request request) {
  final host = request.requestedUri.hasPort
      ? '${request.requestedUri.scheme}://${request.requestedUri.host}:${request.requestedUri.port}'
      : '${request.requestedUri.scheme}://${request.requestedUri.host}';

  final config = {
    'authorization_endpoint': '$host/auth/authorize',
    'token_endpoint': '$host/auth/token',
    'revocation_endpoint': '$host/auth/revoke',
    'registration_endpoint': '$host/auth/register',
    'grant_types_supported': [
      'authorization_code',
      'refresh_token',
    ],
    'scopes_supported': [
      'launch/patient',
      'offline_access',
      'system/*.*',
      'user/*.*',
      'user/*.rs',
      'user/*.cruds',
      'patient/*.*',
      'patient/*.rs',
    ],
    'response_types_supported': ['code'],
    'code_challenge_methods_supported': ['S256'],
    'capabilities': [
      'launch-standalone',
      'authorize-post',
      'client-public',
      'context-standalone-patient',
      'permission-offline',
      'permission-patient',
      'permission-user',
      'permission-v2',
    ],
  };

  return Response.ok(
    jsonEncode(config),
    headers: {'Content-Type': 'application/json'},
  );
}
