import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// OWASP ASVS 5.0.0 V14.3.2 (L2; release JSON, read 2026-10-17, verbatim):
/// "Verify that the application sets sufficient anti-caching HTTP response
/// header fields (i.e., Cache-Control: no-store) so that sensitive data is
/// not cached in browsers." REVIEW-2026-10-17 finding 16: a Patient read, a
/// search and $everything carried no Cache-Control at all.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    token = await issueTestToken(db, scopes: ['user/*.*']);
    await db.saveResource(fhir.Patient(id: 'p1'.toFhirString));
  });

  tearDown(() => db.close());

  for (final path in [
    '/Patient/p1',
    '/Patient?_id=p1',
    r'/Patient/p1/$everything',
    '/Patient/p1/_history',
    '/Patient/nobody',
  ]) {
    test('an authenticated GET $path is not to be stored', () async {
      final r = await handler(testRequest('GET', path, authToken: token));
      expect(r.headers['cache-control'], 'no-store', reason: path);
      expect(r.headers['pragma'], 'no-cache');
    });
  }

  test('the public capability statement may still be cached', () async {
    final r = await handler(testRequest('GET', '/metadata'));
    expect(r.statusCode, 200);
    expect(r.headers['cache-control'], isNot('no-store'));
  });
}
