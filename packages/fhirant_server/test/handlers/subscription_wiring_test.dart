import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/bundle_handler.dart';
import 'package:fhirant_server/src/handlers/resource_handler.dart';
import 'package:fhirant_server/src/services/subscription_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// The write path is where a subscription earns its keep. The service having
/// tests proves the engine works; these prove it is actually reached.
void main() {
  late FhirAntDb db;
  late List<http.Request> sent;
  late SubscriptionService subscriptions;

  setUp(() {
    db = FhirAntDb(NativeDatabase.memory());
    sent = [];
    subscriptions = SubscriptionService(
      db,
      httpClient: MockClient((request) async {
        sent.add(request);
        return http.Response('', 200);
      }),
    );
  });
  tearDown(() async => db.close());

  Future<void> activeSubscriptionOnObservations() async {
    await db.saveResource(
      fhir.Subscription.fromJson({
        'resourceType': 'Subscription',
        'id': 's1',
        'status': 'active',
        'reason': 'test',
        'criteria': 'Observation',
        'channel': {
          'type': 'rest-hook',
          'endpoint': 'https://example.org/hook',
        },
      }),
    );
  }

  Map<String, dynamic> observationJson({String id = 'o1'}) => {
        'resourceType': 'Observation',
        'id': id,
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '1975-2'},
          ],
        },
      };

  test('a POST notifies a matching subscription', () async {
    await activeSubscriptionOnObservations();

    final response = await postResourceHandler(
      Request(
        'POST',
        Uri.parse('http://localhost:8080/Observation'),
        body: jsonEncode(observationJson()),
      ),
      'Observation',
      db,
      subscriptions: subscriptions,
    );

    expect(response.statusCode, equals(201));
    expect(sent, hasLength(1));
    expect(sent.single.url.toString(), equals('https://example.org/hook'));
  });

  test('a PUT notifies a matching subscription', () async {
    await activeSubscriptionOnObservations();

    final response = await putResourceHandler(
      Request(
        'PUT',
        Uri.parse('http://localhost:8080/Observation/o1'),
        body: jsonEncode(observationJson()),
      ),
      'Observation',
      'o1',
      db,
      subscriptions: subscriptions,
    );

    expect(response.statusCode, anyOf(equals(200), equals(201)));
    expect(sent, hasLength(1));
  });

  test('a POSTed Subscription is activated by the server, not the client',
      () async {
    // The client asks for `requested`. R4 subscription.html says the server
    // decides, so what comes back and what is stored must both be `active`.
    final response = await postResourceHandler(
      Request(
        'POST',
        Uri.parse('http://localhost:8080/Subscription'),
        body: jsonEncode({
          'resourceType': 'Subscription',
          'status': 'requested',
          'reason': 'test',
          'criteria': 'Observation',
          'channel': {
            'type': 'rest-hook',
            'endpoint': 'https://example.org/hook',
          },
        }),
      ),
      'Subscription',
      db,
      subscriptions: subscriptions,
    );

    expect(response.statusCode, equals(201));
    final body = jsonDecode(await response.readAsString());
    expect((body as Map<String, dynamic>)['status'], equals('active'));
  });

  test('a Subscription the server cannot honour comes back as error', () async {
    final response = await postResourceHandler(
      Request(
        'POST',
        Uri.parse('http://localhost:8080/Subscription'),
        body: jsonEncode({
          'resourceType': 'Subscription',
          'status': 'requested',
          'reason': 'test',
          'criteria': 'Observation',
          'channel': {'type': 'email', 'endpoint': 'mailto:a@example.org'},
        }),
      ),
      'Subscription',
      db,
      subscriptions: subscriptions,
    );

    final body =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(body['status'], equals('error'));
    expect(body['error'], contains('email'));
  });

  test('a transaction Bundle notifies once per written resource, after commit',
      () async {
    await activeSubscriptionOnObservations();

    final response = await bundleHandler(
      Request(
        'POST',
        Uri.parse('http://localhost:8080/'),
        body: jsonEncode({
          'resourceType': 'Bundle',
          'type': 'transaction',
          'entry': [
            {
              'resource': observationJson(id: 'a'),
              'request': {'method': 'PUT', 'url': 'Observation/a'},
            },
            {
              'resource': observationJson(id: 'b'),
              'request': {'method': 'PUT', 'url': 'Observation/b'},
            },
          ],
        }),
      ),
      db,
      subscriptions: subscriptions,
    );

    expect(response.statusCode, equals(200));
    expect(sent, hasLength(2));
  });

  test('a rolled back transaction notifies nobody', () async {
    // The entries are durable only if the whole Bundle commits. Telling a
    // subscriber about a resource that was rolled back cannot be taken back:
    // the POST has already left.
    await activeSubscriptionOnObservations();

    final response = await bundleHandler(
      Request(
        'POST',
        Uri.parse('http://localhost:8080/'),
        body: jsonEncode({
          'resourceType': 'Bundle',
          'type': 'transaction',
          'entry': [
            {
              'resource': observationJson(id: 'a'),
              'request': {'method': 'PUT', 'url': 'Observation/a'},
            },
            {
              // No resource on a PUT: the entry fails and the Bundle rolls
              // back, including entry one.
              'request': {'method': 'PUT', 'url': 'Observation/b'},
            },
          ],
        }),
      ),
      db,
      subscriptions: subscriptions,
    );

    expect(response.statusCode, greaterThanOrEqualTo(400));
    expect(sent, isEmpty);
    expect(
      await db.getResource(fhir.R4ResourceType.Observation, 'a'),
      isNull,
      reason: 'the rollback must have removed entry one too',
    );
  });

  test('a DELETE notifies nobody', () async {
    // R4 subscription.html: "there is no notification when a resource is
    // deleted".
    await activeSubscriptionOnObservations();
    await db.saveResource(fhir.Observation.fromJson(observationJson()));

    final response = await bundleHandler(
      Request(
        'POST',
        Uri.parse('http://localhost:8080/'),
        body: jsonEncode({
          'resourceType': 'Bundle',
          'type': 'transaction',
          'entry': [
            {
              'request': {'method': 'DELETE', 'url': 'Observation/o1'},
            },
          ],
        }),
      ),
      db,
      subscriptions: subscriptions,
    );

    expect(response.statusCode, equals(200));
    expect(sent, isEmpty);
  });
}
