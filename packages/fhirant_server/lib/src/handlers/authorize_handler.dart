import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/auth/credential_check.dart';
import 'package:fhirant_server/src/utils/smart_scopes.dart';
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
/// - code_challenge, code_challenge_method=S256: PKCE. SMART App Launch
///   STU2 app-launch.html (fetched 2026-09-07): "SMART servers SHALL support
///   the `S256` `code_challenge_method` and SHALL NOT support the `plain`
///   method", and both parameters are "required". Before this PKCE was
///   optional and `plain` was accepted (REVIEW-2026-09-06 finding 10).
///
/// Optional:
/// - aud: the FHIR server URL (audience)
/// - launch: EHR launch context (optional)
///
/// Three rules every path here applies (finding 1, 7, 10):
/// - the scope issued is the requested scope intersected with the account's
///   grant ([SmartScopeEnforcer.grantScopes]), never the request verbatim;
/// - credentials go through [checkCredentials], so failures here count
///   toward the same lockout as `/auth/login`;
/// - `redirect_uri` is pinned per `client_id` on first use, and a later
///   request for the same client with a different redirect is refused
///   without redirecting (RFC 6749 §3.1.2.4 forbids redirecting to an
///   invalid redirect_uri). Loopback redirects may vary their port
///   (RFC 8252 §7.3).

/// Handle GET /auth/authorize — return HTML login form.
Future<Response> authorizeGetHandler(
  Request request,
  FhirAntDb dbInterface,
) async {
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
    return _errorToClient(
      dbInterface,
      clientId,
      redirectUri,
      state,
      'unsupported_response_type',
      'Only response_type=code is supported',
    );
  }

  if (clientId == null || clientId.isEmpty) {
    return Response(
      400,
      body: _errorPage('Missing required parameter: client_id'),
      headers: {'Content-Type': 'text/html'},
    );
  }

  if (redirectUri == null || redirectUri.isEmpty) {
    return Response(
      400,
      body: _errorPage('Missing required parameter: redirect_uri'),
      headers: {'Content-Type': 'text/html'},
    );
  }

  // The checks that need no credentials run before the form is shown, so a
  // person is not asked for a password on a request that cannot succeed.
  final pinned = await _redirectPinProblem(dbInterface, clientId, redirectUri);
  if (pinned != null) {
    return Response(
      400,
      body: _errorPage(pinned),
      headers: {'Content-Type': 'text/html'},
    );
  }
  final problem = _requestProblem(request, state, aud) ??
      _pkceProblem(codeChallenge, codeChallengeMethod);
  if (problem != null) {
    return _errorToClient(
      dbInterface,
      clientId,
      redirectUri,
      state,
      'invalid_request',
      problem,
    );
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
  Request request,
  FhirAntDb dbInterface,
) async {
  try {
    // Parse form body
    final body = await request.readAsString();
    final params = Uri.splitQueryString(body);

    final responseType = params['response_type'];
    final clientId = params['client_id'];
    final redirectUri = params['redirect_uri'];
    final scope = params['scope'] ?? '';
    final state = params['state'] ?? '';
    final codeChallenge = params['code_challenge'] ?? '';
    final codeChallengeMethod = params['code_challenge_method'] ?? '';
    final aud = params['aud'] ?? '';
    final username = params['username'];
    final password = params['password'];

    if (responseType != 'code') {
      return await _errorToClient(
        dbInterface,
        clientId,
        redirectUri,
        state,
        'unsupported_response_type',
        'Only response_type=code is supported',
      );
    }

    if (clientId == null || clientId.isEmpty) {
      return Response(
        400,
        body: _errorPage('Missing client_id'),
        headers: {'Content-Type': 'text/html'},
      );
    }

    if (redirectUri == null || redirectUri.isEmpty) {
      return Response(
        400,
        body: _errorPage('Missing redirect_uri'),
        headers: {'Content-Type': 'text/html'},
      );
    }

    Response form(String error) => Response.ok(
          _loginForm(
            clientId: clientId,
            redirectUri: redirectUri,
            scope: scope,
            state: state,
            codeChallenge: codeChallenge,
            codeChallengeMethod: codeChallengeMethod,
            aud: aud,
            errorMessage: error,
          ),
          headers: {'Content-Type': 'text/html; charset=utf-8'},
        );

    final problem = _requestProblem(request, state, aud);
    if (problem != null) {
      return await _errorToClient(
        dbInterface,
        clientId,
        redirectUri,
        state,
        'invalid_request',
        problem,
      );
    }

    if (username == null ||
        username.isEmpty ||
        password == null ||
        password.isEmpty) {
      return form('Username and password are required');
    }

    final outcome = await _authorize(
      dbInterface,
      clientId: clientId,
      redirectUri: redirectUri,
      scope: scope,
      state: state,
      codeChallenge: codeChallenge,
      codeChallengeMethod: codeChallengeMethod,
      username: username,
      password: password,
    );
    switch (outcome) {
      case _Issued(redirectUrl: final url):
        return Response(302, headers: {'Location': url});
      case _Denied(description: final message):
        return form(message);
      case _Invalid(:final error, :final description, :final redirectable):
        if (redirectable) {
          return await _errorToClient(
            dbInterface,
            clientId,
            redirectUri,
            state,
            error,
            description,
          );
        }
        return Response(
          400,
          body: _errorPage(description),
          headers: {'Content-Type': 'text/html'},
        );
    }
  } catch (e, stackTrace) {
    FhirantLogging().logError('Authorization failed', e, stackTrace);
    return Response(
      400,
      body: _errorPage('Authorization failed'),
      headers: {'Content-Type': 'text/html'},
    );
  }
}

/// Also supports a JSON-based authorize for programmatic clients.
///
/// POST /auth/authorize with Content-Type: application/json
/// Returns JSON { "code": "...", "redirect_uri": "...?code=...&state=..." }
/// instead of an HTTP redirect.
Future<Response> authorizeJsonHandler(
  Request request,
  FhirAntDb dbInterface,
) async {
  try {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;

    final responseType = body['response_type'] as String?;
    final clientId = body['client_id'] as String?;
    final redirectUri = body['redirect_uri'] as String?;
    final scope = body['scope'] as String? ?? '';
    final state = body['state'] as String? ?? '';
    final codeChallenge = body['code_challenge'] as String? ?? '';
    final codeChallengeMethod = body['code_challenge_method'] as String? ?? '';
    final aud = body['aud'] as String? ?? '';
    final username = body['username'] as String?;
    final password = body['password'] as String?;

    Response error(int status, String error, String description) => Response(
          status,
          body: jsonEncode({
            'error': error,
            'error_description': description,
          }),
          headers: {'Content-Type': 'application/json'},
        );

    if (responseType != 'code') {
      return error(
        400,
        'unsupported_response_type',
        'Only response_type=code is supported',
      );
    }

    if (clientId == null || clientId.isEmpty) {
      return error(400, 'invalid_request', 'client_id is required');
    }

    if (redirectUri == null || redirectUri.isEmpty) {
      return error(400, 'invalid_request', 'redirect_uri is required');
    }
    final problem = _requestProblem(request, state, aud);
    if (problem != null) {
      return error(400, 'invalid_request', problem);
    }

    if (username == null || password == null) {
      return error(
        400,
        'invalid_request',
        'username and password are required',
      );
    }

    final outcome = await _authorize(
      dbInterface,
      clientId: clientId,
      redirectUri: redirectUri,
      scope: scope,
      state: state,
      codeChallenge: codeChallenge,
      codeChallengeMethod: codeChallengeMethod,
      username: username,
      password: password,
    );
    switch (outcome) {
      case _Issued(:final code, redirectUrl: final url):
        return Response.ok(
          jsonEncode({
            'code': code,
            'state': state,
            'redirect_uri': url,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      case _Denied(:final status, :final description):
        return error(status, 'access_denied', description);
      case _Invalid(error: final code, :final description):
        return error(400, code, description);
    }
  } catch (e, stackTrace) {
    FhirantLogging().logError('Authorization failed', e, stackTrace);
    return Response(
      400,
      body: jsonEncode({
        'error': 'server_error',
        'error_description': 'Authorization failed',
      }),
    );
  }
}

// ── The one authorization decision the three entry points share ───────────

sealed class _Outcome {
  const _Outcome();
}

/// A code was issued; [redirectUrl] carries it back to the client.
class _Issued extends _Outcome {
  const _Issued(this.code, this.redirectUrl);
  final String code;
  final String redirectUrl;
}

/// The request was well formed but the credentials did not authorize it.
class _Denied extends _Outcome {
  const _Denied(this.status, this.description);
  final int status;
  final String description;
}

/// The request itself is not acceptable. [redirectable] says whether the
/// error may be sent to the redirect_uri (it may not when the redirect_uri
/// is the problem).
class _Invalid extends _Outcome {
  const _Invalid(this.error, this.description, {this.redirectable = true});
  final String error;
  final String description;
  final bool redirectable;
}

Future<_Outcome> _authorize(
  FhirAntDb db, {
  required String clientId,
  required String redirectUri,
  required String scope,
  required String state,
  required String codeChallenge,
  required String codeChallengeMethod,
  required String username,
  required String password,
}) async {
  final pinned = await _redirectPinProblem(db, clientId, redirectUri);
  if (pinned != null) {
    return _Invalid('invalid_request', pinned, redirectable: false);
  }
  final pkce = _pkceProblem(codeChallenge, codeChallengeMethod);
  if (pkce != null) return _Invalid('invalid_request', pkce);

  final User user;
  switch (await checkCredentials(db, username, password)) {
    case CredentialOk(user: final u):
      user = u;
    case CredentialInvalid():
      return const _Denied(401, 'Invalid username or password');
    case CredentialInactive():
      return const _Denied(403, 'Account is deactivated');
    case CredentialLocked(minutesRemaining: final minutes):
      return _Denied(
        423,
        'Account is locked. Try again in $minutes minute(s).',
      );
  }

  final held = user.scopes != null && user.scopes!.isNotEmpty
      ? (jsonDecode(user.scopes!) as List<dynamic>).cast<String>()
      : SmartScopeEnforcer.defaultScopesForRole(user.role);
  final requested =
      scope.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  final granted = SmartScopeEnforcer.grantScopes(
    requested,
    held,
    patientContext: user.patientId != null,
  );
  // A request made only of resource scopes that the account does not hold
  // is refused, not answered with an empty grant that looks like success.
  if (SmartScopeEnforcer.resourceScopesOf(requested).isNotEmpty &&
      SmartScopeEnforcer.resourceScopesOf(granted).isEmpty) {
    return const _Invalid(
      'invalid_scope',
      "None of the requested scopes is within this account's grant",
    );
  }

  // First use of this client_id: pin its redirect_uri. Done only after the
  // credentials passed, so an unauthenticated caller cannot squat a client
  // id by naming it first.
  await db.registerOAuthClient(clientId, redirectUri);

  final code = _uuid.v4();
  await db.createAuthorizationCode(
    code: code,
    clientId: clientId,
    userId: user.id,
    redirectUri: redirectUri,
    scope: granted.join(' '),
    codeChallenge: codeChallenge,
    codeChallengeMethod: codeChallengeMethod,
    expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  );

  final redirectParams = {
    'code': code,
    if (state.isNotEmpty) 'state': state,
  };
  final redirectUrl = Uri.parse(redirectUri)
      .replace(queryParameters: redirectParams)
      .toString();
  return _Issued(code, redirectUrl);
}

/// Sends an authorization error to the client's redirect_uri only when that
/// redirect_uri is the one registered for [clientId]; otherwise the error
/// is shown as a page. RFC 6749 §4.1.2.1 (read 2026-09-08): "If the request
/// fails due to a missing, invalid, or mismatching redirection URI, or if
/// the client identifier is missing or invalid, the authorization server
/// SHOULD inform the resource owner of the error and MUST NOT automatically
/// redirect the user-agent to the invalid redirection URI." An unknown
/// client's redirect_uri is unvalidated, and an unsupported response_type
/// used to be redirected there before any pin was checked, an open redirect
/// (REVIEW-2026-09-08 row 15).
Future<Response> _errorToClient(
  FhirAntDb db,
  String? clientId,
  String? redirectUri,
  String state,
  String error,
  String description,
) async {
  if (clientId != null &&
      clientId.isNotEmpty &&
      redirectUri != null &&
      redirectUri.isNotEmpty) {
    final pinned = await db.getOAuthClientRedirect(clientId);
    if (pinned != null && _sameRedirect(pinned, redirectUri)) {
      return _errorRedirect(redirectUri, state, error, description);
    }
  }
  return Response(
    400,
    body: _errorPage('$error: $description'),
    headers: {'Content-Type': 'text/html'},
  );
}

/// Why an authorization request is refused before anything else is looked
/// at, or null. SMART App Launch STU2 app-launch.html, authorization
/// request parameters (read 2026-09-08): `state` "required … The parameter
/// SHALL be used for preventing cross-site request forgery or session
/// fixation attacks"; `aud` "required … URL of the EHR resource server from
/// which the app wishes to retrieve FHIR data. This parameter prevents
/// leaking a genuine bearer token to a counterfeit resource server", and
/// the resource server "validates that the aud parameter associated with
/// the authorization … matches the resource server's own FHIR endpoint".
/// This server is both, so it checks at authorization: `aud` must be the
/// origin the request came to (with or without a trailing slash). Both used
/// to be optional and `aud` was never read (REVIEW-2026-09-08 row 16).
String? _requestProblem(Request request, String state, String aud) {
  if (state.isEmpty) return 'state is required';
  if (aud.isEmpty) return 'aud is required';
  final here = request.requestedUri;
  final origin = here.hasPort
      ? '${here.scheme}://${here.host}:${here.port}'
      : '${here.scheme}://${here.host}';
  final offered = aud.endsWith('/') ? aud.substring(0, aud.length - 1) : aud;
  if (offered != origin) {
    return 'aud does not name this server ($origin)';
  }
  return null;
}

/// Why a PKCE pair is unacceptable, or null when it is fine.
String? _pkceProblem(String codeChallenge, String codeChallengeMethod) {
  if (codeChallenge.isEmpty) {
    return 'code_challenge is required (PKCE, method S256)';
  }
  if (codeChallengeMethod != 'S256') {
    return 'code_challenge_method must be S256; '
        '"$codeChallengeMethod" is not supported';
  }
  return null;
}

/// Why [redirectUri] is refused for [clientId], or null when it is the pinned
/// one, an equivalent loopback address, or the client is new.
Future<String?> _redirectPinProblem(
  FhirAntDb db,
  String clientId,
  String redirectUri,
) async {
  final pinned = await db.getOAuthClientRedirect(clientId);
  if (pinned == null || _sameRedirect(pinned, redirectUri)) return null;
  return 'redirect_uri does not match the one registered for this '
      'client_id';
}

/// Exact match, except that two loopback URIs match regardless of port:
/// RFC 8252 §7.3, a native app's loopback redirect "MAY" use any port and
/// "the authorization server MUST allow any port to be specified at the
/// time of the request for loopback IP redirect URIs" (quoted from the RFC
/// as read 2026-09-07).
bool _sameRedirect(String pinned, String offered) {
  if (pinned == offered) return true;
  final a = Uri.tryParse(pinned);
  final b = Uri.tryParse(offered);
  if (a == null || b == null) return false;
  const loopback = {'127.0.0.1', 'localhost', '::1', '[::1]'};
  if (!loopback.contains(a.host) || !loopback.contains(b.host)) return false;
  return a.scheme == b.scheme && a.path == b.path;
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
      ? '<div style="color:#d32f2f;background:#fdecea;padding:10px;border-radius:4px;margin-bottom:16px;">${_escapeHtml(errorMessage)}</div>'
      : '';

  return '''
<!DOCTYPE html>
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
  return '''
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Authorization Error</title></head>
<body>
  <h1>Authorization Error</h1>
  <p>${_escapeHtml(message)}</p>
</body>
</html>''';
}

Response _errorRedirect(
  String? redirectUri,
  String state,
  String error,
  String description,
) {
  if (redirectUri == null || redirectUri.isEmpty) {
    return Response(
      400,
      body: _errorPage(description),
      headers: {'Content-Type': 'text/html'},
    );
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
