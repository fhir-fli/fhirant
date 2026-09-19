import 'dart:async';

import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

/// REVIEW-2026-09-17 S2. The hourly cleanup's steps were awaited straight
/// in the `Timer.periodic` callback with no try/catch. An async callback's
/// exception is uncaught, and an uncaught exception ends a Dart CLI process
/// (the review's probe: "database is locked" from the callback, exit 255).
/// The sweep is now `hourlyCleanup`: each step is guarded, so a failing
/// step is logged, the later steps still run, and nothing reaches the zone.
void main() {
  late MockFhirAntDb db;
  late FhirAntDb real;
  late FhirAntServer server;

  setUp(() {
    db = MockFhirAntDb();
    // The constructor reads `fhirDao` (for the base URL); the mock has none.
    real = FhirAntDb(NativeDatabase.memory());
    when(() => db.fhirDao).thenReturn(real.fhirDao);
    server = FhirAntServer(db, jwtSecret: 'test-secret');
  });
  tearDown(() => real.close());

  test('a step that throws is contained and the later steps still run',
      () async {
    when(() => db.cleanupRevokedTokens())
        .thenThrow(StateError('database is locked'));
    when(() => db.cleanupAuthorizationCodes()).thenAnswer((_) async {});
    when(() => db.optimizeStatistics())
        .thenThrow(StateError('database is locked'));

    // The zone is what the timer's callback runs in: an error that reaches
    // it is what ended the process.
    Object? escaped;
    await runZonedGuarded(
      () => server.hourlyCleanup(),
      (e, _) => escaped = e,
    );

    expect(escaped, isNull);
    verify(() => db.cleanupRevokedTokens()).called(1);
    verify(() => db.cleanupAuthorizationCodes()).called(1);
    verify(() => db.optimizeStatistics()).called(1);
  });

  test('every step throwing still completes', () async {
    when(() => db.cleanupRevokedTokens()).thenThrow(Exception('a'));
    when(() => db.cleanupAuthorizationCodes()).thenThrow(Exception('b'));
    when(() => db.optimizeStatistics()).thenThrow(Exception('c'));
    // The export sweep and the subscription sweep hit unstubbed mock
    // methods, which throw too.
    await expectLater(server.hourlyCleanup(), completes);
  });
}
