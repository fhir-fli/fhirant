import 'dart:async';

import 'package:fhirant/src/screens/dashboard_screen.dart';
import 'package:fhirant/src/services/database_service.dart';
import 'package:fhirant/src/services/server_service.dart';
import 'package:fhirant/src/state/server_state.dart';
import 'package:fhirant_db/fhirant_db.dart' show FhirAntDb;
import 'package:fhirant_server/fhirant_server.dart' show RequestLogEntry;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _UninitializedDb extends DatabaseService {
  @override
  FhirAntDb get db => throw StateError('DatabaseService not initialized');
}

class _FakeServerService extends ServerService {
  _FakeServerService() : super(_UninitializedDb());

  final _log = StreamController<RequestLogEntry>.broadcast();

  @override
  Stream<RequestLogEntry> get requestLog => _log.stream;

  @override
  Future<void> start(int port, {bool devMode = false}) async {}

  @override
  Future<void> stop() async {}

  void emit(RequestLogEntry entry) => _log.add(entry);
}

/// Sizes the app is actually used at: a small phone, a common phone, and a
/// tablet. An overflow at any of them is a layout bug the dashboard would show
/// a user, and `flutter_test` fails the test when one is painted.
const _sizes = <String, Size>{
  'small phone': Size(320, 568),
  'phone': Size(412, 915),
  'tablet': Size(834, 1112),
};

Widget _app(ServerState state) => MaterialApp(
      home: ChangeNotifierProvider<ServerState>.value(
        value: state,
        child: const DashboardScreen(),
      ),
    );

/// Pumps a fixed number of frames rather than `pumpAndSettle`: a running
/// server installs a 10-second periodic timer to refresh resource counts, so
/// the tree never settles and `pumpAndSettle` would hang until its timeout.
Future<void> _pumpAt(WidgetTester tester, Size size, Widget app) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(app);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  for (final entry in _sizes.entries) {
    testWidgets('the dashboard lays out on a ${entry.key} while stopped',
        (tester) async {
      final state = ServerState(
        dbService: _UninitializedDb(),
        serverService: _FakeServerService(),
      );

      await _pumpAt(tester, entry.value, _app(state));

      expect(find.text('FHIR ANT'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the dashboard lays out on a ${entry.key} while running',
        (tester) async {
      final service = _FakeServerService();
      final state = ServerState(
        dbService: _UninitializedDb(),
        serverService: service,
      );
      // startServer awaits NetworkInterface.list — real I/O, which never
      // completes inside testWidgets' fake-async zone. runAsync gives it a
      // real one.
      await tester.runAsync(state.startServer);
      addTearDown(state.dispose);

      await _pumpAt(tester, entry.value, _app(state));

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a long request path does not overflow the log card',
      (tester) async {
    final service = _FakeServerService();
    final state = ServerState(
      dbService: _UninitializedDb(),
      serverService: service,
    );
    await tester.runAsync(state.startServer);
    addTearDown(state.dispose);

    // Inside runAsync: the log stream is a real broadcast controller, so the
    // event only reaches the listener on a real event loop, not the fake clock
    // testWidgets installs.
    await tester.runAsync(() async {
      service.emit(
        RequestLogEntry(
          timestamp: DateTime(2026, 8, 24),
          method: 'GET',
          // A search URL of the kind a client really sends — long enough to
          // test whether the card wraps or clips it.
          path: '/Patient?name=Faulkenberry&birthdate=ge1980-01-01'
              '&_sort=-_lastUpdated&_count=50&_include=Patient:organization',
          statusCode: 200,
          durationMs: 12,
          clientIp: '192.168.1.100',
        ),
      );
      await Future<void>.delayed(Duration.zero);
    });

    await _pumpAt(tester, const Size(320, 568), _app(state));

    expect(tester.takeException(), isNull);
  });
}
