import 'dart:async';

import 'package:fhirant/src/config/security_config.dart';
import 'package:fhirant/src/services/database_service.dart';
import 'package:fhirant/src/services/server_service.dart';
import 'package:fhirant/src/state/server_state.dart';
import 'package:fhirant_db/fhirant_db.dart' show FhirAntDb;
import 'package:fhirant_server/fhirant_server.dart' show RequestLogEntry;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A database service that never initializes. `ServerState` only reaches the
/// database from `_refreshResourceCounts`, which swallows every error, so this
/// lets the start/stop path be exercised without a real SQLite file — and it
/// also proves a failing database does not take the server down with it.
class _UninitializedDb extends DatabaseService {
  @override
  FhirAntDb get db => throw StateError('DatabaseService not initialized');
}

/// A server service whose start/stop can be made to succeed or fail, and which
/// records the auth posture it was started with.
class _FakeServerService extends ServerService {
  _FakeServerService({this.failOnStart = false}) : super(_UninitializedDb());

  final bool failOnStart;
  final _log = StreamController<RequestLogEntry>.broadcast();

  int? startedPort;
  bool? startedDevMode;
  int startCalls = 0;
  int stopCalls = 0;

  @override
  Stream<RequestLogEntry> get requestLog => _log.stream;

  @override
  Future<void> start(int port, {bool devMode = false}) async {
    startCalls++;
    if (failOnStart) throw StateError('port $port already in use');
    startedPort = port;
    startedDevMode = devMode;
  }

  @override
  Future<void> stop() async => stopCalls++;

  void emit(RequestLogEntry entry) => _log.add(entry);

  Future<void> disposeLog() => _log.close();
}

RequestLogEntry _entry(String path) => RequestLogEntry(
      timestamp: DateTime(2026, 8, 24),
      method: 'GET',
      path: path,
      statusCode: 200,
      durationMs: 1,
      clientIp: '10.0.0.2',
    );

ServerState _state(_FakeServerService service) => ServerState(
      dbService: _UninitializedDb(),
      serverService: service,
    );

void main() {
  setUp(() {
    // The constructor reads the persisted auth posture; with no mock values
    // SharedPreferences throws on the platform channel.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('auth posture', () {
    test('a fresh install follows the ship default', () async {
      final state = _state(_FakeServerService());
      expect(state.devMode, kDefaultAuthDisabled);
    });

    test('an operator choice overrides the ship default and is persisted',
        () async {
      final state = _state(_FakeServerService())
        ..devMode = !kDefaultAuthDisabled;
      expect(state.devMode, !kDefaultAuthDisabled);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('auth_disabled'), !kDefaultAuthDisabled);
    });

    test('a persisted choice is loaded over the ship default', () async {
      SharedPreferences.setMockInitialValues(
        <String, Object>{'auth_disabled': !kDefaultAuthDisabled},
      );
      final state = _state(_FakeServerService());
      // The load is async; pump the microtask queue.
      await Future<void>.delayed(Duration.zero);
      expect(state.devMode, !kDefaultAuthDisabled);
    });

    test('the posture cannot be flipped while the server is running', () async {
      final service = _FakeServerService();
      final state = _state(service);
      final startingPosture = state.devMode;

      await state.startServer();
      expect(state.isRunning, isTrue);

      state.devMode = !startingPosture;

      expect(
        state.devMode,
        startingPosture,
        reason: 'flipping auth off under a live server would change what the '
            'running listener enforces without restarting it',
      );
    });

    test('the posture in force is the one handed to the server', () async {
      final service = _FakeServerService();
      final state = _state(service)..devMode = false;

      await state.startServer();

      expect(service.startedDevMode, isFalse);
    });
  });

  group('port', () {
    test('defaults to 8080', () {
      expect(_state(_FakeServerService()).port, 8080);
    });

    test('is settable while stopped and is the port the server binds',
        () async {
      final service = _FakeServerService();
      final state = _state(service)..port = 9123;

      await state.startServer();

      expect(service.startedPort, 9123);
    });

    test('cannot be changed while running', () async {
      final state = _state(_FakeServerService())..port = 9123;
      await state.startServer();

      state.port = 7000;

      expect(state.port, 9123);
    });
  });

  group('start and stop', () {
    test('a successful start reports running and clears any prior error',
        () async {
      final state = _state(_FakeServerService());

      await state.startServer();

      expect(state.status, ServerStatus.running);
      expect(state.errorMessage, isNull);
    });

    test('a failing start reports the error rather than running', () async {
      final state = _state(_FakeServerService(failOnStart: true));

      await state.startServer();

      expect(state.status, ServerStatus.error);
      expect(state.errorMessage, contains('already in use'));
      expect(state.isRunning, isFalse);
    });

    test('a start after a failure is allowed', () async {
      final service = _FakeServerService(failOnStart: true);
      final state = _state(service);
      await state.startServer();

      await state.startServer();

      expect(service.startCalls, 2);
    });

    test('starting an already-running server is a no-op', () async {
      final service = _FakeServerService();
      final state = _state(service);
      await state.startServer();

      await state.startServer();

      expect(service.startCalls, 1);
    });

    test('stopping a stopped server is a no-op', () async {
      final service = _FakeServerService();
      final state = _state(service);

      await state.stopServer();

      expect(service.stopCalls, 0);
      expect(state.status, ServerStatus.stopped);
    });

    test('a stop returns to stopped', () async {
      final service = _FakeServerService();
      final state = _state(service);
      await state.startServer();

      await state.stopServer();

      expect(state.status, ServerStatus.stopped);
      expect(service.stopCalls, 1);
    });

    test('a database that cannot be reached does not stop the server running',
        () async {
      // _UninitializedDb throws on every access; the counts refresh must
      // swallow that rather than fail the start.
      final state = _state(_FakeServerService());

      await state.startServer();

      expect(state.status, ServerStatus.running);
      expect(state.resourceCounts, isEmpty);
    });
  });

  group('serverUrl', () {
    test('is null while the server is not running', () {
      expect(_state(_FakeServerService()).serverUrl, isNull);
    });

    test('a start does not wait on the address lookup', () async {
      // Enumerating network interfaces is slow and can fail; the server is
      // running whether or not we have worked out how to reach it yet, so
      // startServer must not block on it. The url simply appears later.
      final state = _state(_FakeServerService());

      await state.startServer();

      expect(state.status, ServerStatus.running);
    });
  });

  group('request log', () {
    test('is empty before the server starts', () {
      expect(_state(_FakeServerService()).requestLog, isEmpty);
    });

    test('shows the newest request first', () async {
      final service = _FakeServerService();
      final state = _state(service);
      await state.startServer();

      service
        ..emit(_entry('/Patient/1'))
        ..emit(_entry('/Patient/2'));
      await Future<void>.delayed(Duration.zero);

      expect(
        state.requestLog.map((e) => e.path).toList(),
        ['/Patient/2', '/Patient/1'],
      );
    });

    test('keeps at most 200 entries, dropping the oldest', () async {
      final service = _FakeServerService();
      final state = _state(service);
      await state.startServer();

      for (var i = 0; i < 205; i++) {
        service.emit(_entry('/Patient/$i'));
      }
      await Future<void>.delayed(Duration.zero);

      expect(state.requestLog.length, 200);
      expect(state.requestLog.first.path, '/Patient/204');
      expect(state.requestLog.last.path, '/Patient/5');
    });

    test('stops collecting once the server is stopped', () async {
      final service = _FakeServerService();
      final state = _state(service);
      await state.startServer();
      service.emit(_entry('/Patient/1'));
      await Future<void>.delayed(Duration.zero);

      await state.stopServer();
      service.emit(_entry('/Patient/2'));
      await Future<void>.delayed(Duration.zero);

      expect(state.requestLog.map((e) => e.path), ['/Patient/1']);
    });
  });

  group('resourceCounts', () {
    test('is unmodifiable', () {
      final counts = _state(_FakeServerService()).resourceCounts;
      expect(counts.clear, throwsUnsupportedError);
    });
  });

  test('listeners are notified when the status changes', () async {
    final state = _state(_FakeServerService());
    var notifications = 0;
    state.addListener(() => notifications++);

    await state.startServer();

    expect(notifications, greaterThan(0));
  });
}
