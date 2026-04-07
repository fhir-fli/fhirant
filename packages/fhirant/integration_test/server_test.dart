import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:fhirant/main.dart' show FhirantStartup;
import 'package:fhirant/src/services/database_service.dart';
import 'package:fhirant/src/services/server_service.dart';
import 'package:fhirant/src/state/server_state.dart';

/// Integration test that launches the app, starts the server in dev mode,
/// and verifies FHIR endpoints work on the actual device.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late DatabaseService dbService;
  late ServerService serverService;
  late HttpClient httpClient;
  const port = 8089; // Use non-default port to avoid conflicts
  final baseUrl = 'http://localhost:$port';

  /// Helper to make HTTP requests and return (statusCode, decodedBody).
  Future<(int, dynamic)> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final req = await httpClient.openUrl(method, uri);
    req.headers.set('content-type', 'application/fhir+json');
    headers?.forEach((k, v) => req.headers.set(k, v));
    if (body != null) {
      req.write(jsonEncode(body));
    }
    final resp = await req.close();
    final respBody = await resp.transform(utf8.decoder).join();
    dynamic decoded;
    try {
      decoded = jsonDecode(respBody);
    } catch (_) {
      decoded = respBody;
    }
    return (resp.statusCode, decoded);
  }

  setUpAll(() async {
    httpClient = HttpClient();
    dbService = DatabaseService();
    await dbService.initialize();
    serverService = ServerService(dbService);
  });

  tearDownAll(() async {
    await serverService.stop();
    httpClient.close();
  });

  group('App UI', () {
    testWidgets('launches and shows dashboard', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ServerState(
            dbService: dbService,
            serverService: serverService,
          ),
          child: const FhirantStartup(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify dashboard elements are present
      expect(find.text('FHIR ANT'), findsOneWidget);
      expect(find.text('FHIR Server'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('Dev Mode'), findsOneWidget);
    });

    testWidgets('can start server in dev mode', (tester) async {
      final state = ServerState(
        dbService: dbService,
        serverService: serverService,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: const FhirantStartup(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify dev mode is on by default
      final devSwitch = find.byType(Switch);
      expect(devSwitch, findsOneWidget);

      // Set port to our test port
      state.port = port;
      await tester.pumpAndSettle();

      // Tap Start
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Server should be running
      expect(state.status, ServerStatus.running);
      expect(state.devMode, isTrue);
    });
  });

  group('Server endpoints (on-device)', () {
    // These tests run after the server is started by the UI test above.
    // If running independently, start the server first.

    setUpAll(() async {
      // Ensure server is running in dev mode
      if (!serverService.isRunning) {
        await serverService.start(port, devMode: true);
      }
    });

    test('GET /health returns 200', () async {
      final (status, body) = await request('GET', '/health');
      expect(status, 200);
      expect(body['status'], isNotNull);
    });

    test('GET /metadata returns CapabilityStatement', () async {
      final (status, body) = await request('GET', '/metadata');
      expect(status, 200);
      expect(body['resourceType'], 'CapabilityStatement');
    });

    test('POST /Patient creates a resource', () async {
      final (status, body) = await request('POST', '/Patient', body: {
        'resourceType': 'Patient',
        'name': [
          {
            'family': 'IntegrationTest',
            'given': ['Flutter'],
          }
        ],
      });
      expect(status, 201);
      expect(body['resourceType'], 'Patient');
      expect(body['id'], isNotNull);
    });

    test('GET /Patient searches resources', () async {
      final (status, body) = await request('GET', '/Patient');
      expect(status, 200);
      expect(body['resourceType'], 'Bundle');
      expect(body['type'], 'searchset');
    });

    test('CRUD lifecycle works', () async {
      // Create
      final (createStatus, created) =
          await request('POST', '/Patient', body: {
        'resourceType': 'Patient',
        'name': [
          {'family': 'CrudTest'}
        ],
      });
      expect(createStatus, 201);
      final id = created['id'] as String;

      // Read
      final (readStatus, read) = await request('GET', '/Patient/$id');
      expect(readStatus, 200);
      expect(read['name'][0]['family'], 'CrudTest');

      // Update
      read['name'][0]['family'] = 'CrudUpdated';
      final (updateStatus, updated) =
          await request('PUT', '/Patient/$id', body: read);
      expect(updateStatus, 200);
      expect(updated['name'][0]['family'], 'CrudUpdated');

      // Delete
      final (deleteStatus, _) = await request('DELETE', '/Patient/$id');
      expect(deleteStatus, 204);
    });

    test('_elements filters response fields', () async {
      // Create a resource
      final (_, created) = await request('POST', '/Patient', body: {
        'resourceType': 'Patient',
        'name': [
          {'family': 'ElementsTest'}
        ],
        'gender': 'female',
        'birthDate': '1990-01-01',
      });
      final id = created['id'];

      // Read with _elements
      final (status, body) =
          await request('GET', '/Patient/$id?_elements=name');
      expect(status, 200);
      expect(body['resourceType'], 'Patient');
      expect(body['name'], isNotNull);
      // gender and birthDate should be stripped
      expect(body['gender'], isNull);
      expect(body['birthDate'], isNull);

      // Clean up
      await request('DELETE', '/Patient/$id');
    });

    test('transaction Bundle works', () async {
      final (status, body) = await request('POST', '/', body: {
        'resourceType': 'Bundle',
        'type': 'transaction',
        'entry': [
          {
            'fullUrl': 'urn:uuid:tx-patient-1',
            'resource': {
              'resourceType': 'Patient',
              'name': [
                {'family': 'TxTest1'}
              ],
            },
            'request': {'method': 'POST', 'url': 'Patient'},
          },
          {
            'fullUrl': 'urn:uuid:tx-patient-2',
            'resource': {
              'resourceType': 'Patient',
              'name': [
                {'family': 'TxTest2'}
              ],
            },
            'request': {'method': 'POST', 'url': 'Patient'},
          },
        ],
      });
      expect(status, 200);
      expect(body['resourceType'], 'Bundle');
      expect(body['type'], 'transaction-response');
      expect((body['entry'] as List).length, 2);
    });

    test('history returns versions', () async {
      // Create
      final (_, created) = await request('POST', '/Patient', body: {
        'resourceType': 'Patient',
        'name': [
          {'family': 'HistoryV1'}
        ],
      });
      final id = created['id'];

      // Wait briefly so version timestamps differ
      await Future.delayed(const Duration(seconds: 1));

      // Update
      created['name'][0]['family'] = 'HistoryV2';
      await request('PUT', '/Patient/$id', body: created);

      // Get history
      final (status, body) =
          await request('GET', '/Patient/$id/_history');
      expect(status, 200);
      expect(body['resourceType'], 'Bundle');
      expect(body['type'], 'history');
      expect((body['entry'] as List).length, greaterThanOrEqualTo(2));

      // Clean up
      await request('DELETE', '/Patient/$id');
    });

    test('backup and restore work', () async {
      // Create some data first
      await request('POST', '/Observation', body: {
        'resourceType': 'Observation',
        'status': 'final',
        'code': {
          'text': 'BackupTest',
        },
      });

      // Backup
      final (backupStatus, backup) = await request('POST', '/\$backup');
      expect(backupStatus, 200);
      expect(backup['resourceType'], 'Bundle');
      expect(backup['type'], 'collection');
      expect((backup['entry'] as List?)?.isNotEmpty ?? false, isTrue);

      // Restore with a small test bundle
      final (restoreStatus, restoreResult) =
          await request('POST', '/\$restore', body: {
        'resourceType': 'Bundle',
        'type': 'collection',
        'entry': [
          {
            'resource': {
              'resourceType': 'Patient',
              'name': [
                {'family': 'Restored'}
              ],
            },
          },
        ],
      });
      expect(restoreStatus, 200);
      expect(restoreResult['resourceType'], 'OperationOutcome');
    });
  });
}
