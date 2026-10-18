import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-10-17 finding 12. `Subscription.channel.header` carries what
/// the server sends with a rest-hook delivery, and R4B subscription.html's
/// own example puts a credential there (hl7.org/fhir/R4B/subscription.html,
/// read whole 2026-10-17, verbatim): `"header": ["Authorization: Bearer
/// secret-token-abc-123"]`; 2.46.5: "Servers are responsible for ensuring
/// appropriate security is employed for each channel." A rest-hook
/// Subscription is system authority's to create or change
/// (`storeRefusal`), but any token that could read Subscriptions read the
/// header (measured over HTTP: a second clinician's search returned it).
/// Without system authority the header is now removed from every response
/// and the resource labelled REDACTED (v3-ObservationValue, "remove any
/// portion of the resource that is not authorized to be access, used, or
/// disclosed").
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String clinician;
  late String admin;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    clinician =
        await issueTestToken(db, username: 'clin', scopes: ['user/*.*']);
    admin = await issueTestToken(
      db,
      username: 'adm',
      role: 'admin',
      scopes: ['system/*.*'],
    );
    await db.saveResource(
      fhir.Resource.fromJson({
        'resourceType': 'Subscription',
        'id': 'hook',
        'status': 'active',
        'reason': 'x',
        'criteria': 'Observation?code:text=x',
        'channel': {
          'type': 'rest-hook',
          'endpoint': 'https://lab.example/hook',
          'header': ['Authorization: Bearer secret-token-abc-123'],
        },
      }),
    );
    await db.saveResource(
      fhir.Resource.fromJson({
        'resourceType': 'Subscription',
        'id': 'ws',
        'status': 'active',
        'reason': 'x',
        'criteria': 'Observation?code:text=x',
        'channel': {'type': 'websocket'},
      }),
    );
  });

  tearDown(() => db.close());

  Future<String> get(String path, String token) async {
    final r = await handler(testRequest('GET', path, authToken: token));
    expect(r.statusCode, 200, reason: path);
    return r.readAsString();
  }

  bool redacted(Map<String, dynamic> subscription) =>
      ((subscription['meta'] as Map?)?['security'] as List? ?? const [])
          .any((s) => (s as Map)['code'] == 'REDACTED');

  for (final path in [
    '/Subscription/hook',
    '/Subscription',
    '/Subscription/hook/_history',
    '/Subscription/hook/_history/1',
    '/Subscription?_id=hook',
  ]) {
    test('a clinician never sees the header: GET $path', () async {
      final body = await get(path, clinician);
      expect(body, isNot(contains('secret-token-abc-123')));
    });
  }

  test('the read is labelled REDACTED and keeps the rest', () async {
    final s = jsonDecode(await get('/Subscription/hook', clinician))
        as Map<String, dynamic>;
    expect(redacted(s), isTrue);
    expect((s['channel'] as Map)['endpoint'], 'https://lab.example/hook');
  });

  test('a batch GET entry is redacted too', () async {
    final r = await handler(
      testRequest(
        'POST',
        '/',
        body: jsonEncode({
          'resourceType': 'Bundle',
          'type': 'batch',
          'entry': [
            {
              'request': {'method': 'GET', 'url': 'Subscription/hook'},
            },
          ],
        }),
        authToken: clinician,
      ),
    );
    expect(await r.readAsString(), isNot(contains('secret-token-abc-123')));
  });

  test('system authority sees the header', () async {
    final body = await get('/Subscription/hook', admin);
    expect(body, contains('secret-token-abc-123'));
  });

  test('a Subscription with no header is not labelled', () async {
    final s = jsonDecode(await get('/Subscription/ws', clinician))
        as Map<String, dynamic>;
    expect(redacted(s), isFalse);
  });
}
