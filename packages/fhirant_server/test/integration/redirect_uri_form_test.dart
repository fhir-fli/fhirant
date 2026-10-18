import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// RFC 6749 3.1.2 (rfc-editor.org/rfc/rfc6749.txt, read 2026-10-18,
/// verbatim): "The redirection endpoint URI MUST be an absolute URI as
/// defined by [RFC3986] Section 4.3." and "The endpoint URI MUST NOT include
/// a fragment component." OWASP ASVS 5.0.0 V1.2.2 (L1): when a URL is built
/// from untrusted data, "Ensure that only safe URL protocols are permitted
/// (e.g., disallow javascript: or data:)"; the code goes out in a Location
/// built from this value. REVIEW-2026-10-17 finding 19: on a client's first
/// use, `javascript:alert(1)`, a URI with a fragment and `not a url` were
/// pinned and sent the code. Pinning on first use is settled; this is the
/// form check before it. Custom schemes stay allowed (RFC 8252 native apps).
const password = 'a-long-test-password-9';

void main() {
  late FhirAntDb db;
  late Handler handler;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    await db.createUser(
      username: 'pat',
      passwordHash: PasswordHasher.hashPasswordSync(password, 'salt'),
      salt: 'salt',
      role: 'readonly',
      scopes: '["patient/*.rs"]',
      patientId: 'p1',
    );
  });

  tearDown(() => db.close());

  Map<String, String> params(String client, String redirect) => {
        'response_type': 'code',
        'client_id': client,
        'redirect_uri': redirect,
        'scope': 'patient/*.rs',
        'state': 's',
        'aud': 'http://localhost:8080',
        'code_challenge': 'A' * 43,
        'code_challenge_method': 'S256',
      };

  /// The form (GET), then the sign-in that pins (POST); both answers.
  Future<(Response, Response)> authorize(String client, String redirect) async {
    final form = await handler(
      testRequest(
        'GET',
        '/auth/authorize?${Uri(queryParameters: params(client, redirect)).query}',
        headers: {'accept': 'text/html,*/*;q=0.8'},
      ),
    );
    final signIn = await handler(
      testRequest(
        'POST',
        '/auth/authorize',
        body: Uri(
          queryParameters: {
            ...params(client, redirect),
            'username': 'pat',
            'password': password,
          },
        ).query,
        headers: {
          'accept': 'text/html,*/*;q=0.8',
          'content-type': 'application/x-www-form-urlencoded',
        },
      ),
    );
    return (form, signIn);
  }

  var n = 0;
  for (final bad in [
    'javascript:alert(1)',
    'JavaScript:alert(1)',
    'data:text/html,<script>alert(1)</script>',
    'https://app.example/cb#fragment',
    'not a url',
    '/relative/cb',
    'https:///no-host',
  ]) {
    test('refused, not pinned: $bad', () async {
      final client = 'bad-${n++}';
      final (form, signIn) = await authorize(client, bad);
      expect(form.statusCode, 400, reason: await form.readAsString());
      expect(signIn.statusCode, 400, reason: await signIn.readAsString());
      expect(signIn.headers['location'], isNull, reason: 'no code sent');
      expect(await db.getOAuthClientRedirect(client), isNull);
    });
  }

  for (final good in [
    'https://app.example/cb',
    'http://127.0.0.1:9000/cb',
    'com.example.app:/oauth2redirect',
  ]) {
    test('allowed: $good', () async {
      final client = 'good-${n++}';
      final (form, signIn) = await authorize(client, good);
      expect(form.statusCode, 200, reason: await form.readAsString());
      expect(signIn.statusCode, 302, reason: await signIn.readAsString());
      expect(signIn.headers['location'], startsWith(good));
      expect(await db.getOAuthClientRedirect(client), good);
    });
  }
}
