import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/meta_handler.dart';
import 'package:fhirant_server/src/handlers/patch_handler.dart';
import 'package:fhirant_server/src/services/subscription_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// REVIEW-2026-09-17 A7. `patchResourceHandler` took no SubscriptionService,
/// so a PATCH of a Subscription the server had set to `error` stored the
/// client's `active`, and a PATCH of any resource notified no subscriber.
/// `$meta-add` and `$meta-delete` write a new version too and notified
/// nothing. Every write now goes through the service, as PUT and POST do.
void main() {
  late FhirAntDb db;
  late List<http.Request> sent;
  late SubscriptionService subs;

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
    sent = [];
    subs = SubscriptionService(
      db,
      httpClient: MockClient((request) async {
        sent.add(request);
        return http.Response('', 200);
      }),
    );
  });
  tearDown(() => db.close());

  Request patch(String path, List<Map<String, dynamic>> ops) => Request(
        'PATCH',
        Uri.parse('http://localhost$path'),
        body: jsonEncode(ops),
        headers: {'content-type': 'application/json-patch+json'},
      );

  Request meta(String path, Map<String, dynamic> meta) => Request(
        'POST',
        Uri.parse('http://localhost$path'),
        body: jsonEncode({
          'resourceType': 'Parameters',
          'parameter': [
            {'name': 'meta', 'valueMeta': meta},
          ],
        }),
        headers: {'content-type': 'application/fhir+json'},
      );

  Future<void> hookOnObservations() async {
    // Created as the server creates one: through the service, which
    // activates it.
    final activated = await subs.activate(
      fhir.Subscription.fromJson({
        'resourceType': 'Subscription',
        'id': 's1',
        'status': 'requested',
        'reason': 'test',
        'criteria': 'Observation?status=final',
        'channel': {
          'type': 'rest-hook',
          'endpoint': 'https://example.org/hook',
        },
      }),
    );
    await db.saveResource(activated);
    expect(activated.status.valueString, 'active');
  }

  Future<void> observation() => db.saveResource(
        fhir.Observation.fromJson({
          'resourceType': 'Observation',
          'id': 'o1',
          'status': 'preliminary',
          'code': {'text': 'x'},
        }),
      );

  test('a PATCH cannot set a Subscription active that the server set error',
      () async {
    // A channel this server cannot deliver: the service marks it `error`.
    final refused = await subs.activate(
      fhir.Subscription.fromJson({
        'resourceType': 'Subscription',
        'id': 's-err',
        'status': 'requested',
        'reason': 'test',
        'criteria': 'Observation?status=final',
        'channel': {'type': 'email', 'endpoint': 'mailto:x@example.org'},
      }),
    );
    expect(refused.status.valueString, 'error');
    await db.saveResource(refused);

    final res = await patchResourceHandler(
      patch('/Subscription/s-err', [
        {'op': 'replace', 'path': '/status', 'value': 'active'},
      ]),
      'Subscription',
      's-err',
      db,
      subscriptions: subs,
    );
    expect(res.statusCode, 200, reason: await res.readAsString());
    final stored = await db.getResource(
      fhir.R4ResourceType.Subscription,
      's-err',
    );
    expect((stored! as fhir.Subscription).status.valueString, 'error');
  });

  test('a PATCH notifies a matching subscriber', () async {
    await hookOnObservations();
    await observation();
    final res = await patchResourceHandler(
      patch('/Observation/o1', [
        {'op': 'replace', 'path': '/status', 'value': 'final'},
      ]),
      'Observation',
      'o1',
      db,
      subscriptions: subs,
    );
    expect(res.statusCode, 200, reason: await res.readAsString());
    await subs.drain();
    expect(sent.map((r) => r.url.toString()), ['https://example.org/hook']);
  });

  test(r'$meta-add and $meta-delete notify a matching subscriber', () async {
    await hookOnObservations();
    await db.saveResource(
      fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': 'o1',
        'status': 'final',
        'code': {'text': 'x'},
      }),
    );
    const tag = {
      'tag': [
        {'system': 'urn:x', 'code': 'y'},
      ],
    };
    final added = await metaAddHandler(
      meta(r'/Observation/o1/$meta-add', tag),
      'Observation',
      'o1',
      db,
      subscriptions: subs,
    );
    expect(added.statusCode, 200, reason: await added.readAsString());
    final deleted = await metaDeleteHandler(
      meta(r'/Observation/o1/$meta-delete', tag),
      'Observation',
      'o1',
      db,
      subscriptions: subs,
    );
    expect(deleted.statusCode, 200, reason: await deleted.readAsString());
    await subs.drain();
    expect(sent, hasLength(2));
  });
}
