import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-10-17 finding 5. The tokens carried no unique claim, so two
/// sessions of one account minted in the same second were the same string
/// (measured over HTTP: two back-to-back logins, byte-identical on the first
/// try). Revocation is by token hash, so one device logging out ended the
/// other's session, and a refresh in the same second as the login handed
/// back the refresh token it had just revoked. RFC 7519 §4.1.7
/// (rfc-editor.org/rfc/rfc7519.txt, read 2026-10-18, verbatim): 'The "jti"
/// (JWT ID) claim provides a unique identifier for the JWT. The identifier
/// value MUST be assigned in a manner that ensures that there is a
/// negligible probability that the same value will be accidentally assigned
/// to a different data object'.
void main() {
  test('two access tokens with the same claims in the same instant differ', () {
    final jwt = JwtService(testJwtSecret);
    String mint() =>
        jwt.generateToken(userId: 1, username: 'u', role: 'clinician');
    String refresh() =>
        jwt.generateRefreshToken(userId: 1, username: 'u', role: 'clinician');
    expect(mint(), isNot(mint()));
    expect(refresh(), isNot(refresh()));
  });

  test(
      'ending one session leaves a second session of the same account '
      'working', () async {
    final server = await createTestServer();
    await server.db.saveResource(fhir.Patient(id: 'p1'.toFhirString));
    final phone = await issueTestToken(
      server.db,
      username: 'nurse',
      scopes: ['user/*.*'],
    );
    final tablet = await issueTestToken(
      server.db,
      username: 'nurse',
      scopes: ['user/*.*'],
    );

    final out = await server.handler(
      testRequest(
        'POST',
        '/auth/logout',
        body: jsonEncode({}),
        authToken: phone,
      ),
    );
    expect(out.statusCode, 200);

    final read = await server.handler(
      testRequest('GET', '/Patient/p1', authToken: tablet),
    );
    expect(read.statusCode, 200, reason: await read.readAsString());
    final gone = await server.handler(
      testRequest('GET', '/Patient/p1', authToken: phone),
    );
    expect(gone.statusCode, 401, reason: 'the session that logged out ended');
    await server.db.close();
  });
}
