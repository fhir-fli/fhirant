import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// OAuth 2.0 Authorization Endpoint.
///
/// GET  /auth/authorize — Renders an HTML login form with the OAuth params.
/// POST /auth/authorize — Validates credentials, generates authorization code,
///                        redirects to redirect_uri with code + state.
///
/// Required query parameters (GET) or form fields (POST):
/// - response_type: must be "code"
/// - client_id: the OAuth client identifier
/// - redirect_uri: where to redirect after authorization
/// - scope: space-separated SMART scopes
/// - state: opaque CSRF token
///
/// Optional:
/// - code_challenge: PKCE code challenge (required for public clients)
/// - code_challenge_method: "S256" (recommended) or "plain"
/// - aud: the FHIR server URL (audience)
/// - launch: EHR launch context (optional)

/// Handle GET /auth/authorize — return HTML login form.
Future<Response> authorizeGetHandler(Request request) async {
  final params = request.url.queryParameters;

  final responseType = params['response_type'];
  final clientId = params['client_id'];
  final redirectUri = params['redirect_uri'];
  final scope = params['scope'] ?? '';
  final state = params['state'] ?? '';
  final codeChallenge = params['code_challenge'] ?? '';
  final codeChallengeMethod = params['code_challenge_method'] ?? '';
  final aud = params['aud'] ?? '';

  if (responseType != 'code') {
    return _errorRedirect(
      redirectUri,
      state,
      'unsupported_response_type',
      'Only response_type=code is supported',
    );
  }

  if (clientId == null || clientId.isEmpty) {
    return Response(400,
        body: _errorPage('Missing required parameter: client_id'),
        headers: {'Content-Type': 'text/html'});
  }

  if (redirectUri == null || redirectUri.isEmpty) {
    return Response(400,
        body: _errorPage('Missing required parameter: redirect_uri'),
        headers: {'Content-Type': 'text/html'});
  }

  // Return the login form
  return Response.ok(
    _loginForm(
      clientId: clientId,
      redirectUri: redirectUri,
      scope: scope,
      state: state,
      codeChallenge: codeChallenge,
      codeChallengeMethod: codeChallengeMethod,
      aud: aud,
    ),
    headers: {'Content-Type': 'text/html; charset=utf-8'},
  );
}

/// Handle POST /auth/authorize — validate credentials and issue code.
Future<Response> authorizePostHandler(
    Request request, FhirAntDb dbInterface) async {
  try {
    // Parse form body
    final body = await request.readAsString();
    final params = Uri.splitQueryString(body);

    final responseType = params['response_type'];
    final clientId = params['client_id'];
    final redirectUri = params['redirect_uri'];
    final scope = params['scope'] ?? '';
    final state = params['state'] ?? '';
    final codeChallenge = params['code_challenge'];
    final codeChallengeMethod = params['code_challenge_method'];
    final username = params['username'];
    final password = params['password'];

    if (responseType != 'code') {
      return _errorRedirect(
        redirectUri,
        state,
        'unsupported_response_type',
        'Only response_type=code is supported',
      );
    }

    if (clientId == null || clientId.isEmpty) {
      return Response(400,
          body: _errorPage('Missing client_id'),
          headers: {'Content-Type': 'text/html'});
    }

    if (redirectUri == null || redirectUri.isEmpty) {
      return Response(400,
          body: _errorPage('Missing redirect_uri'),
          headers: {'Content-Type': 'text/html'});
    }

    if (username == null ||
        username.isEmpty ||
        password == null ||
        password.isEmpty) {
      return Response.ok(
        _loginForm(
          clientId: clientId,
          redirectUri: redirectUri,
          scope: scope,
          state: state,
          codeChallenge: codeChallenge ?? '',
          codeChallengeMethod: codeChallengeMethod ?? '',
          aud: '',
          errorMessage: 'Username and password are required',
        ),
        headers: {'Content-Type': 'text/html; charset=utf-8'},
      );
    }

    // Authenticate user
    final user = await dbInterface.getUserByUsername(username);
    if (user == null ||
        !PasswordHasher.verifyPassword(
            password, user.salt, user.passwordHash)) {
      return Response.ok(
        _loginForm(
          clientId: clientId,
          redirectUri: redirectUri,
          scope: scope,
          state: state,
          codeChallenge: codeChallenge ?? '',
          codeChallengeMethod: codeChallengeMethod ?? '',
          aud: '',
          errorMessage: 'Invalid username or password',
        ),
        headers: {'Content-Type': 'text/html; charset=utf-8'},
      );
    }

    if (!user.active) {
      return Response.ok(
        _loginForm(
          clientId: clientId,
          redirectUri: redirectUri,
          scope: scope,
          state: state,
          codeChallenge: codeChallenge ?? '',
          codeChallengeMethod: codeChallengeMethod ?? '',
          aud: '',
          errorMessage: 'Account is deactivated',
        ),
        headers: {'Content-Type': 'text/html; charset=utf-8'},
      );
    }

    // Generate authorization code
    final code = _uuid.v4();
    final expiresAt = DateTime.now().add(const Duration(minutes: 5));

    await dbInterface.createAuthorizationCode(
      code: code,
      clientId: clientId,
      userId: user.id,
      redirectUri: redirectUri,
      scope: scope,
      codeChallenge:
          (codeChallenge != null && codeChallenge.isNotEmpty)
              ? codeChallenge
              : null,
      codeChallengeMethod:
          (codeChallengeMethod != null && codeChallengeMethod.isNotEmpty)
              ? codeChallengeMethod
              : null,
      expiresAt: expiresAt,
    );

    // Redirect to redirect_uri with code and state
    final redirectParams = {
      'code': code,
      if (state.isNotEmpty) 'state': state,
    };
    final redirectUrl = Uri.parse(redirectUri)
        .replace(queryParameters: redirectParams)
        .toString();

    return Response(302, headers: {'Location': redirectUrl});
  } catch (e) {
    return Response(400,
        body: _errorPage('Authorization failed: $e'),
        headers: {'Content-Type': 'text/html'});
  }
}

/// Also supports a JSON-based authorize for programmatic clients.
///
/// POST /auth/authorize with Content-Type: application/json
/// Returns JSON { "code": "...", "redirect_uri": "...?code=...&state=..." }
/// instead of an HTTP redirect.
Future<Response> authorizeJsonHandler(
    Request request, FhirAntDb dbInterface) async {
  try {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;

    final responseType = body['response_type'] as String?;
    final clientId = body['client_id'] as String?;
    final redirectUri = body['redirect_uri'] as String?;
    final scope = body['scope'] as String? ?? '';
    final state = body['state'] as String? ?? '';
    final codeChallenge = body['code_challenge'] as String?;
    final codeChallengeMethod = body['code_challenge_method'] as String?;
    final username = body['username'] as String?;
    final password = body['password'] as String?;

    if (responseType != 'code') {
      return Response(400,
          body: jsonEncode({
            'error': 'unsupported_response_type',
            'error_description': 'Only response_type=code is supported',
          }));
    }

    if (clientId == null || clientId.isEmpty) {
      return Response(400,
          body: jsonEncode({
            'error': 'invalid_request',
            'error_description': 'client_id is required',
          }));
    }

    if (redirectUri == null || redirectUri.isEmpty) {
      return Response(400,
          body: jsonEncode({
            'error': 'invalid_request',
            'error_description': 'redirect_uri is required',
          }));
    }

    if (username == null || password == null) {
      return Response(400,
          body: jsonEncode({
            'error': 'invalid_request',
            'error_description': 'username and password are required',
          }));
    }

    // Authenticate
    final user = await dbInterface.getUserByUsername(username);
    if (user == null ||
        !PasswordHasher.verifyPassword(
            password, user.salt, user.passwordHash)) {
      return Response(401,
          body: jsonEncode({
            'error': 'access_denied',
            'error_description': 'Invalid credentials',
          }));
    }

    if (!user.active) {
      return Response(403,
          body: jsonEncode({
            'error': 'access_denied',
            'error_description': 'Account is deactivated',
          }));
    }

    // Generate authorization code
    final code = _uuid.v4();
    final expiresAt = DateTime.now().add(const Duration(minutes: 5));

    await dbInterface.createAuthorizationCode(
      code: code,
      clientId: clientId,
      userId: user.id,
      redirectUri: redirectUri,
      scope: scope,
      codeChallenge:
          (codeChallenge != null && codeChallenge.isNotEmpty)
              ? codeChallenge
              : null,
      codeChallengeMethod:
          (codeChallengeMethod != null && codeChallengeMethod.isNotEmpty)
              ? codeChallengeMethod
              : null,
      expiresAt: expiresAt,
    );

    // Return code in JSON (for programmatic/testing use)
    final redirectParams = {
      'code': code,
      if (state.isNotEmpty) 'state': state,
    };
    final fullRedirectUrl = Uri.parse(redirectUri)
        .replace(queryParameters: redirectParams)
        .toString();

    return Response.ok(
      jsonEncode({
        'code': code,
        'state': state,
        'redirect_uri': fullRedirectUrl,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response(400,
        body: jsonEncode({
          'error': 'server_error',
          'error_description': 'Authorization failed: $e',
        }));
  }
}

// ── HTML helpers ──────────────────────────────────────────────────────────

String _loginForm({
  required String clientId,
  required String redirectUri,
  required String scope,
  required String state,
  required String codeChallenge,
  required String codeChallengeMethod,
  required String aud,
  String? errorMessage,
}) {
  final errorHtml = errorMessage != null
      ? '<div style="color:#d32f2f;background:#fdecea;padding:10px;border-radius:4px;margin-bottom:16px;">$errorMessage</div>'
      : '';

  return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>FHIRant - Authorize</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f5; display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; }
    .card { background: white; padding: 32px; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); width: 100%; max-width: 400px; }
    h1 { margin: 0 0 8px; font-size: 24px; color: #333; }
    .subtitle { color: #666; margin-bottom: 24px; font-size: 14px; }
    .scope-info { background: #f0f7ff; padding: 10px; border-radius: 4px; margin-bottom: 16px; font-size: 13px; color: #1565c0; }
    label { display: block; font-weight: 500; margin-bottom: 4px; color: #555; font-size: 14px; }
    input[type=text], input[type=password] { width: 100%; padding: 10px; border: 1px solid #ddd; border-radius: 4px; font-size: 16px; box-sizing: border-box; margin-bottom: 16px; }
    button { width: 100%; padding: 12px; background: #1976d2; color: white; border: none; border-radius: 4px; font-size: 16px; cursor: pointer; }
    button:hover { background: #1565c0; }
  </style>
</head>
<body>
  <div class="card">
    <h1>FHIRant</h1>
    <div class="subtitle">Application <strong>${_escapeHtml(clientId)}</strong> is requesting access</div>
    ${scope.isNotEmpty ? '<div class="scope-info">Requested scopes: ${_escapeHtml(scope)}</div>' : ''}
    $errorHtml
    <form method="POST" action="/auth/authorize">
      <input type="hidden" name="response_type" value="code">
      <input type="hidden" name="client_id" value="${_escapeHtml(clientId)}">
      <input type="hidden" name="redirect_uri" value="${_escapeHtml(redirectUri)}">
      <input type="hidden" name="scope" value="${_escapeHtml(scope)}">
      <input type="hidden" name="state" value="${_escapeHtml(state)}">
      <input type="hidden" name="code_challenge" value="${_escapeHtml(codeChallenge)}">
      <input type="hidden" name="code_challenge_method" value="${_escapeHtml(codeChallengeMethod)}">
      <input type="hidden" name="aud" value="${_escapeHtml(aud)}">
      <label for="username">Username</label>
      <input type="text" id="username" name="username" required autofocus>
      <label for="password">Password</label>
      <input type="password" id="password" name="password" required>
      <button type="submit">Authorize</button>
    </form>
  </div>
</body>
</html>''';
}

String _errorPage(String message) {
  return '''<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Authorization Error</title></head>
<body>
  <h1>Authorization Error</h1>
  <p>${_escapeHtml(message)}</p>
</body>
</html>''';
}

Response _errorRedirect(
    String? redirectUri, String state, String error, String description) {
  if (redirectUri == null || redirectUri.isEmpty) {
    return Response(400,
        body: _errorPage(description),
        headers: {'Content-Type': 'text/html'});
  }
  final params = {
    'error': error,
    'error_description': description,
    if (state.isNotEmpty) 'state': state,
  };
  final url =
      Uri.parse(redirectUri).replace(queryParameters: params).toString();
  return Response(302, headers: {'Location': url});
}

String _escapeHtml(String text) {
  return text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}
