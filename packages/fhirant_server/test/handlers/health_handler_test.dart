import 'dart:convert';

import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:fhirant_server/src/handlers/health_handler.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

void main() {
  late MockFhirAntDb mockDb;

  setUp(() {
    mockDb = MockFhirAntDb();
  });

  group('healthHandler', () {
    test('returns ok status when DB is connected', () async {
      when(() => mockDb.getUserCount()).thenAnswer((_) async => 5);

      final startTime = DateTime.now().subtract(const Duration(seconds: 30));
      final request = Request('GET', Uri.parse('http://localhost:8080/health'));

      final response = await healthHandler(request, mockDb, startTime);

      expect(response.statusCode, equals(200));
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['status'], equals('ok'));
      expect(body['database'], equals('connected'));
      expect(body['version'], equals('1.0.0'));
      expect(body['uptime'], isA<int>());
      expect(body['timestamp'], isA<String>());
    });

    test('returns degraded status when DB throws', () async {
      when(() => mockDb.getUserCount()).thenThrow(Exception('DB is down'));

      final startTime = DateTime.now().subtract(const Duration(seconds: 10));
      final request = Request('GET', Uri.parse('http://localhost:8080/health'));

      final response = await healthHandler(request, mockDb, startTime);

      expect(response.statusCode, equals(200));
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['status'], equals('degraded'));
      expect(body['database'], equals('error'));
    });

    test('uptime reflects elapsed time', () async {
      when(() => mockDb.getUserCount()).thenAnswer((_) async => 0);

      final startTime = DateTime.now().subtract(const Duration(seconds: 60));
      final request = Request('GET', Uri.parse('http://localhost:8080/health'));

      final response = await healthHandler(request, mockDb, startTime);

      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final uptime = body['uptime'] as int;
      // Should be at least 59 seconds (accounting for test execution time)
      expect(uptime, greaterThanOrEqualTo(59));
    });

    test('Content-Type is application/json', () async {
      when(() => mockDb.getUserCount()).thenAnswer((_) async => 0);

      final startTime = DateTime.now();
      final request = Request('GET', Uri.parse('http://localhost:8080/health'));

      final response = await healthHandler(request, mockDb, startTime);

      expect(response.headers['content-type'], equals('application/json'));
    });
  });
}
