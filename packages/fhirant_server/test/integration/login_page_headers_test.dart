import 'dart:io';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-17 A16: the login page and the authorization error pages
/// carried no frame or content-security header. OWASP Clickjacking Defense
/// Cheat Sheet (verbatim): `X-Frame-Options: DENY` "The 'DENY' setting is
/// recommended unless a specific need has been identified for framing";
/// `frame-ancestors 'none'` "prevents any domain from framing the content".
void main() {
  late FhirAntDb db;
  late Handler handler;
  late Directory exportDir;

  setUp(() async {
    exportDir = await Directory.systemTemp.createTemp('loginpage');
    final server = await createTestServer(exportDir: exportDir.path);
    db = server.db;
    handler = server.handler;
  });

  tearDown(() async {
    await db.close();
    await exportDir.delete(recursive: true);
  });

  void expectPageHeaders(Response r) {
    expect(r.headers['content-type'], startsWith('text/html'));
    expect(r.headers['x-frame-options'], 'DENY');
    final csp = r.headers['content-security-policy'] ?? '';
    expect(csp, contains("frame-ancestors 'none'"));
    expect(csp, contains("form-action 'self'"));
    expect(csp, contains("default-src 'none'"));
    expect(csp, contains("base-uri 'none'"));
    expect(r.headers['x-content-type-options'], 'nosniff');
    expect(r.headers['cache-control'], 'no-store');
  }

  const query = 'response_type=code&client_id=app'
      '&redirect_uri=http%3A%2F%2Flocalhost%2Fcb&scope=user%2F*.rs'
      '&state=xyz&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM'
      '&code_challenge_method=S256&aud=http%3A%2F%2Flocalhost%3A8080';

  test('the login form', () async {
    final r = await handler(testRequest('GET', '/auth/authorize?$query'));
    expect(r.statusCode, 200, reason: await r.readAsString());
    expectPageHeaders(r);
  });

  test('an authorization error page', () async {
    final r = await handler(testRequest('GET', '/auth/authorize'));
    expect(r.statusCode, 400);
    expectPageHeaders(r);
  });

  test('the form shown again after a wrong password', () async {
    final r = await handler(
      testRequest(
        'POST',
        '/auth/authorize',
        headers: {'content-type': 'application/x-www-form-urlencoded'},
        body: '$query&username=nobody-here&password=wrong-password-1',
      ),
    );
    expect(r.statusCode, 200, reason: await r.readAsString());
    expectPageHeaders(r);
  });
}
