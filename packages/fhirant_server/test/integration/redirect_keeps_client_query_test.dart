import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// RFC 6749 3.1.2 (rfc-editor.org/rfc/rfc6749.txt, read 2026-10-18,
/// verbatim): "The endpoint URI MAY include an
/// "application/x-www-form-urlencoded" formatted (per Appendix B) query
/// component ([RFC3986] Section 3.4), which MUST be retained when adding
/// additional query parameters." Found 2026-10-18 while testing
/// REVIEW-2026-10-17 finding 19: for `https://app.example/cb?keep=this` the
/// code went to `https://app.example/cb?code=...&state=s`, the client's own
/// query gone; the error redirect did the same.
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

  Map<String, String> params(String redirect, {String? aud}) => {
        'response_type': 'code',
        'client_id': 'app',
        'redirect_uri': redirect,
        'scope': 'patient/*.rs',
        'state': 's',
        'aud': aud ?? 'http://localhost:8080',
        'code_challenge': 'A' * 43,
        'code_challenge_method': 'S256',
      };

  Future<Response> signIn(String redirect, {String? aud}) async => handler(
        testRequest(
          'POST',
          '/auth/authorize',
          body: Uri(
            queryParameters: {
              ...params(redirect, aud: aud),
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

  const redirect = 'https://app.example/cb?keep=this&tag=a&tag=b';

  test('the code redirect keeps the client query', () async {
    final r = await signIn(redirect);
    expect(r.statusCode, 302, reason: await r.readAsString());
    final location = Uri.parse(r.headers['location']!);
    expect(location.queryParametersAll['keep'], ['this']);
    expect(location.queryParametersAll['tag'], ['a', 'b']);
    expect(location.queryParameters['code'], isNotEmpty);
    expect(location.queryParameters['state'], 's');
  });

  test('an error redirect keeps it too', () async {
    // Pinned by the first sign-in; the second is refused for its aud and
    // the refusal goes to the pinned redirect.
    await signIn(redirect);
    final r = await signIn(redirect, aud: 'https://evil.example/fhir');
    expect(r.statusCode, 302, reason: await r.readAsString());
    final location = Uri.parse(r.headers['location']!);
    expect(location.queryParametersAll['keep'], ['this']);
    expect(location.queryParameters['error'], isNotEmpty);
  });
}
