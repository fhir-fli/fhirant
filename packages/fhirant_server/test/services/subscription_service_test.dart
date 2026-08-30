import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/services/subscription_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Records what the server sent, so delivery is asserted against the request
/// R4 subscription.html describes rather than against what the code happens to
/// build.
class Recorder {
  final List<http.Request> sent = [];
  int status = 200;

  http.Client get client => MockClient((request) async {
        sent.add(request);
        return http.Response('', status);
      });
}

fhir.Subscription subscription({
  String id = 's1',
  String status = 'requested',
  String criteria = 'Observation?code=http://loinc.org|1975-2',
  String channelType = 'rest-hook',
  String? endpoint = 'https://example.org/hook',
  String? payload,
  List<String>? header,
  DateTime? end,
}) =>
    fhir.Subscription.fromJson({
      'resourceType': 'Subscription',
      'id': id,
      'status': status,
      'reason': 'test',
      'criteria': criteria,
      if (end != null) 'end': end.toUtc().toIso8601String(),
      'channel': {
        'type': channelType,
        if (endpoint != null) 'endpoint': endpoint,
        if (payload != null) 'payload': payload,
        if (header != null) 'header': header,
      },
    });

fhir.Observation observation({
  String id = 'o1',
  String code = '1975-2',
}) =>
    fhir.Observation.fromJson({
      'resourceType': 'Observation',
      'id': id,
      'status': 'final',
      'code': {
        'coding': [
          {'system': 'http://loinc.org', 'code': code},
        ],
      },
    });

void main() {
  late FhirAntDb db;
  late Recorder recorder;
  late SubscriptionService service;

  setUp(() {
    db = FhirAntDb(NativeDatabase.memory());
    recorder = Recorder();
    service = SubscriptionService(db, httpClient: recorder.client);
  });
  tearDown(() async => db.close());

  group('criteria are search strings interpreted like REST queries', () {
    test('a bare resource type matches every instance of it', () async {
      await db.saveResource(observation());
      final sub = subscription(criteria: 'Observation');
      expect(await service.matches(sub, observation()), isTrue);
    });

    test('a token search matches only the resources the REST search would',
        () async {
      await db.saveResource(observation(id: 'match'));
      await db.saveResource(observation(id: 'other', code: '9999-9'));

      final sub = subscription();
      expect(await service.matches(sub, observation(id: 'match')), isTrue);
      expect(
        await service.matches(sub, observation(id: 'other', code: '9999-9')),
        isFalse,
      );
    });

    test('a resource of a different type never matches', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'p1',
      });
      await db.saveResource(patient);
      expect(await service.matches(subscription(), patient), isFalse);
    });

    test('an unparseable criteria matches nothing rather than everything',
        () async {
      await db.saveResource(observation());
      final sub = subscription(criteria: 'NotAResourceType?x=1');
      expect(await service.matches(sub, observation()), isFalse);
    });
  });

  group('the server decides the status, per the lifecycle', () {
    test('requested becomes active once the server can process it', () async {
      final activated = await service.activate(subscription());
      expect(activated.status.valueString, equals('active'));
      expect(activated.error, isNull);
    });

    test('an unusable criteria becomes error, with the reason recorded',
        () async {
      final activated =
          await service.activate(subscription(criteria: 'Nonsense?a=b'));
      expect(activated.status.valueString, equals('error'));
      expect(activated.error?.valueString, contains('criteria'));
    });

    test('an unsupported channel is refused, not silently accepted', () async {
      // Telling a client a subscription is active when this server will never
      // deliver on that channel is worse than refusing it.
      final activated =
          await service.activate(subscription(channelType: 'email'));
      expect(activated.status.valueString, equals('error'));
      expect(activated.error?.valueString, contains('email'));
    });

    test('a rest-hook with no endpoint is refused', () async {
      final activated = await service.activate(subscription(endpoint: null));
      expect(activated.status.valueString, equals('error'));
      expect(activated.error?.valueString, contains('endpoint'));
    });

    test('end in the past turns the subscription off', () async {
      final activated = await service.activate(
        subscription(end: DateTime.utc(2020)),
      );
      expect(activated.status.valueString, equals('off'));
    });
  });

  group('rest-hook delivery', () {
    test('an empty payload POSTs an empty body to the endpoint', () async {
      await db.saveResource(subscription(status: 'active'));
      await db.saveResource(observation());

      await service.onResourceChanged(observation());

      expect(recorder.sent, hasLength(1));
      expect(recorder.sent.single.method, equals('POST'));
      expect(
        recorder.sent.single.url.toString(),
        equals('https://example.org/hook'),
      );
      expect(recorder.sent.single.body, isEmpty);
    });

    test('a payload PUTs the resource under the endpoint as a service base',
        () async {
      await db.saveResource(
        subscription(status: 'active', payload: 'application/fhir+json'),
      );
      await db.saveResource(observation());

      await service.onResourceChanged(observation());

      expect(recorder.sent, hasLength(1));
      final request = recorder.sent.single;
      expect(request.method, equals('PUT'));
      expect(
        request.url.toString(),
        equals('https://example.org/hook/Observation/o1'),
      );
      expect(
        (jsonDecode(request.body) as Map<String, dynamic>)['id'],
        equals('o1'),
      );
    });

    test('channel.header is sent, split on the first colon only', () async {
      await db.saveResource(
        subscription(
          status: 'active',
          header: ['Authorization: Bearer abc:def'],
        ),
      );
      await db.saveResource(observation());

      await service.onResourceChanged(observation());

      expect(
        recorder.sent.single.headers['Authorization'],
        equals('Bearer abc:def'),
      );
    });

    test('a resource that does not match is not delivered', () async {
      await db.saveResource(subscription(status: 'active'));
      await db.saveResource(observation(id: 'x', code: '9999-9'));

      await service.onResourceChanged(observation(id: 'x', code: '9999-9'));

      expect(recorder.sent, isEmpty);
    });

    test('a subscription that is not active is not delivered to', () async {
      await db.saveResource(subscription());
      await db.saveResource(observation());

      await service.onResourceChanged(observation());

      expect(recorder.sent, isEmpty);
    });
  });

  group('a failing subscriber does not break the write', () {
    test('a non-2xx response records the error on the subscription', () async {
      recorder.status = 500;
      await db.saveResource(subscription(status: 'active'));
      await db.saveResource(observation());

      await service.onResourceChanged(observation());

      final stored = await db.getResource(
        fhir.R4ResourceType.Subscription,
        's1',
      ) as fhir.Subscription?;
      expect(stored?.status.valueString, equals('error'));
      expect(stored?.error?.valueString, contains('500'));
    });

    test('a subscriber that throws does not throw out of onResourceChanged',
        () async {
      final throwing = SubscriptionService(
        db,
        httpClient: MockClient((_) async => throw const SocketFailure()),
      );
      await db.saveResource(subscription(status: 'active'));
      await db.saveResource(observation());

      await expectLater(
        throwing.onResourceChanged(observation()),
        completes,
      );

      final stored = await db.getResource(
        fhir.R4ResourceType.Subscription,
        's1',
      ) as fhir.Subscription?;
      expect(stored?.status.valueString, equals('error'));
    });

    test('a recovered subscriber returns to active', () async {
      await db.saveResource(
        subscription(status: 'active').copyWith(error: 'old'.toFhirString),
      );
      await db.saveResource(observation());

      await service.onResourceChanged(observation());

      final stored = await db.getResource(
        fhir.R4ResourceType.Subscription,
        's1',
      ) as fhir.Subscription?;
      expect(stored?.status.valueString, equals('active'));
      expect(stored?.error, isNull);
    });
  });
  group('retry and giving up are fhirant policy, not spec rules', () {
    // R4 subscription.html delegates both: "The server may retry the
    // notification a fixed number of times", and "If a subscription fails
    // consistently a server may choose set the subscription status to off".
    // These tests pin fhirant's choice, not a requirement of the standard.
    Future<fhir.Subscription?> stored() async =>
        await db.getResource(fhir.R4ResourceType.Subscription, 's1')
            as fhir.Subscription?;

    test('a failure short of the threshold stays in error and keeps trying',
        () async {
      recorder.status = 500;
      await db.saveResource(subscription(status: 'active'));
      await db.saveResource(observation());

      await service.onResourceChanged(observation());
      expect((await stored())?.status.valueString, equals('error'));

      // Delivered to again on the next write, which is the point of `error`
      // rather than `off`. Before this was fixed the retry never happened:
      // onResourceChanged searched only for `active`, so the first failure
      // silenced a subscription permanently while claiming a status the spec
      // says can revert to active.
      await service.onResourceChanged(observation());
      expect(recorder.sent, hasLength(2));
    });

    test('consecutive failures switch it off and delivery stops', () async {
      recorder.status = 500;
      await db.saveResource(subscription(status: 'active'));
      await db.saveResource(observation());

      for (var i = 0; i < 5; i++) {
        await service.onResourceChanged(observation());
      }

      final off = await stored();
      expect(off?.status.valueString, equals('off'));
      expect(off?.error?.valueString, contains('5 consecutive failures'));

      final attempts = recorder.sent.length;
      await service.onResourceChanged(observation());
      expect(
        recorder.sent,
        hasLength(attempts),
        reason: 'an off subscription is not delivered to again',
      );
    });

    test('the threshold is configurable, because the spec sets no number',
        () async {
      final strict = SubscriptionService(
        db,
        httpClient: recorder.client,
        maxConsecutiveFailures: 2,
      );
      recorder.status = 500;
      await db.saveResource(subscription(status: 'active'));
      await db.saveResource(observation());

      await strict.onResourceChanged(observation());
      expect((await stored())?.status.valueString, equals('error'));
      await strict.onResourceChanged(observation());
      expect((await stored())?.status.valueString, equals('off'));
    });

    test(
        'a success resets the count, so failures spread over time never add up',
        () async {
      await db.saveResource(subscription(status: 'active'));
      await db.saveResource(observation());

      recorder.status = 500;
      for (var i = 0; i < 4; i++) {
        await service.onResourceChanged(observation());
      }
      expect((await stored())?.status.valueString, equals('error'));

      recorder.status = 200;
      await service.onResourceChanged(observation());
      final recovered = await stored();
      expect(recovered?.status.valueString, equals('active'));
      expect(recovered?.error, isNull);

      // Four more failures must not tip it over: the count restarted.
      recorder.status = 500;
      for (var i = 0; i < 4; i++) {
        await service.onResourceChanged(observation());
      }
      expect((await stored())?.status.valueString, equals('error'));
    });

    test('the count lives in an extension under our own namespace', () async {
      // R4 has no element for it, and the URL must never be mistakable for an
      // HL7 one.
      recorder.status = 500;
      await db.saveResource(subscription(status: 'active'));
      await db.saveResource(observation());
      await service.onResourceChanged(observation());

      final extension = (await stored())!.extension_!.single;
      expect(
        extension.url.valueString,
        equals(SubscriptionService.failureCountExtensionUrl),
      );
      expect(extension.url.valueString, startsWith('http://fhirant.'));
      expect((extension.valueX! as fhir.FhirInteger).valueInt, equals(1));
    });
  });
}

class SocketFailure implements Exception {
  const SocketFailure();
}
