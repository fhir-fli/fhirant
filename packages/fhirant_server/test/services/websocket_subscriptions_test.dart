import 'dart:async';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/services/subscription_service.dart';
import 'package:fhirant_server/src/services/websocket_subscriptions.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A sink that records what the server wrote, so the handshake is asserted as
/// wire text against what R4 subscription.html specifies:
///
///   client -> bind :id
///   server -> bound :id
///   server -> ping :id
class RecordingSink implements WebSocketSink {
  final List<Object?> written = [];
  bool closed = false;
  bool throwOnAdd = false;

  @override
  void add(Object? data) {
    if (throwOnAdd) {
      throw StateError('socket is gone');
    }
    written.add(data);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closed = true;
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<Object?> stream) async {}

  @override
  Future<void> get done async {}
}

void main() {
  group('the handshake is exactly what the spec gives', () {
    late WebSocketSubscriptions registry;
    late RecordingSink sink;

    setUp(() {
      registry = WebSocketSubscriptions();
      sink = RecordingSink();
    });

    test('bind :id is answered with bound :id', () {
      expect(registry.handleMessage('bind :s1', sink), equals('bound s1'));
      expect(registry.socketsFor('s1'), equals(1));
    });

    test('bind without the colon works too', () {
      // The spec writes the placeholder as ":id"; real clients send the bare
      // id. Accept both rather than fail a client over punctuation.
      expect(registry.handleMessage('bind s1', sink), equals('bound s1'));
      expect(registry.socketsFor('s1'), equals(1));
    });

    test('anything that is not bind is ignored, not answered', () {
      // Answering an unknown message could leave a client believing it bound.
      expect(registry.handleMessage('hello', sink), isNull);
      expect(registry.handleMessage('bind', sink), isNull);
      expect(registry.handleMessage('bind  ', sink), isNull);
      expect(registry.boundIds, isEmpty);
    });

    test('ping goes to every socket bound to that subscription', () {
      final second = RecordingSink();
      registry
        ..handleMessage('bind :s1', sink)
        ..handleMessage('bind :s1', second);

      expect(registry.ping('s1'), equals(2));
      expect(sink.written, equals(['ping s1']));
      expect(second.written, equals(['ping s1']));
    });

    test('ping to a subscription nobody bound is not an error', () {
      expect(registry.ping('nobody'), equals(0));
    });

    test('a socket that throws is dropped and the others still get the ping',
        () {
      final broken = RecordingSink()..throwOnAdd = true;
      registry
        ..handleMessage('bind :s1', broken)
        ..handleMessage('bind :s1', sink);

      expect(registry.ping('s1'), equals(1));
      expect(sink.written, equals(['ping s1']));
      expect(registry.socketsFor('s1'), equals(1));
    });

    test('release drops a socket from every subscription it bound', () {
      registry
        ..handleMessage('bind :s1', sink)
        ..handleMessage('bind :s2', sink);
      expect(registry.boundIds, containsAll(['s1', 's2']));

      registry.release(sink);

      expect(registry.boundIds, isEmpty);
      expect(registry.ping('s1'), equals(0));
    });
  });

  group('a websocket Subscription end to end', () {
    late FhirAntDb db;
    late WebSocketSubscriptions registry;
    late SubscriptionService service;
    late RecordingSink sink;

    setUp(() {
      db = FhirAntDb(NativeDatabase.memory());
      registry = WebSocketSubscriptions();
      sink = RecordingSink();
      service = SubscriptionService(db, websockets: registry);
    });
    tearDown(() async => db.close());

    fhir.Subscription websocketSubscription({String status = 'requested'}) =>
        fhir.Subscription.fromJson({
          'resourceType': 'Subscription',
          'id': 'ws1',
          'status': status,
          'reason': 'test',
          'criteria': 'Observation',
          'channel': {'type': 'websocket'},
        });

    test('activates with no endpoint, because the client dials in', () async {
      final activated = await service.activate(websocketSubscription());
      expect(activated.status.valueString, equals('active'));
      expect(activated.error, isNull);
    });

    test('a matching write pings the bound socket', () async {
      await db.saveResource(websocketSubscription(status: 'active'));
      registry.handleMessage('bind :ws1', sink);

      final observation = fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': 'o1',
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '1975-2'},
          ],
        },
      });
      await db.saveResource(observation);
      await service.onResourceChanged(observation);

      expect(sink.written, equals(['ping ws1']));
    });

    test('nothing is bound: the write succeeds and nothing is marked in error',
        () async {
      await db.saveResource(websocketSubscription(status: 'active'));

      final observation = fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': 'o1',
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '1975-2'},
          ],
        },
      });
      await db.saveResource(observation);
      await service.onResourceChanged(observation);

      final stored = await db.getResource(
        fhir.R4ResourceType.Subscription,
        'ws1',
      ) as fhir.Subscription?;
      expect(stored?.status.valueString, equals('active'));
      expect(stored?.error, isNull);
    });
  });
}
