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
    'token_endpoint': '$host/auth/login',
    'registration_endpoint': '$host/auth/register',
    'scopes_supported': [
      'system/*.*',
      'user/*.*',
      'user/*.rs',
      'user/*.cruds',
      'patient/*.*',
      'patient/*.rs',
    ],
    'response_types_supported': ['token'],
    'capabilities': [
      'permission-v2',
      'launch-standalone',
    ],
  };

  return Response.ok(
    jsonEncode(config),
    headers: {'Content-Type': 'application/json'},
  );
}
