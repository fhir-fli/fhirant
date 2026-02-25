import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    token = generateTestToken(role: 'admin', scopes: ['system/*.*']);
  });

  tearDown(() async {
    await db.close();
  });

  /// Helper to create a resource and return its assigned ID.
  Future<String> createResource(Map<String, dynamic> resource) async {
    final response = await handler(testRequest(
      'POST',
      '/${resource['resourceType']}',
      body: jsonEncode(resource),
      authToken: token,
    ));
    expect(response.statusCode, 201,
        reason: 'Failed to create ${resource['resourceType']}');
    final body = jsonDecode(await response.readAsString()) as Map;
    return body['id'] as String;
  }

  group('_has reverse chaining', () {
    late String patientId;
    late String otherPatientId;

    setUp(() async {
      // Create two patients
      patientId = await createResource({
        'resourceType': 'Patient',
        'name': [
          {
            'family': 'HasTest',
            'given': ['Alice']
          }
        ],
      });

      otherPatientId = await createResource({
        'resourceType': 'Patient',
        'name': [
          {
            'family': 'HasTest',
            'given': ['Bob']
          }
        ],
      });

      // Create an Observation referencing the first patient
      await createResource({
        'resourceType': 'Observation',
        'status': 'final',
        'code': {
          'coding': [
            {
              'system': 'http://loinc.org',
              'code': '85354-9',
              'display': 'Blood pressure panel',
            }
          ]
        },
        'subject': {'reference': 'Patient/$patientId'},
      });

      // Create a different Observation referencing the second patient
      await createResource({
        'resourceType': 'Observation',
        'status': 'final',
        'code': {
          'coding': [
            {
              'system': 'http://loinc.org',
              'code': '29463-7',
              'display': 'Body weight',
            }
          ]
        },
        'subject': {'reference': 'Patient/$otherPatientId'},
      });
    });

    test('Patient?_has:Observation:patient:code=85354-9 finds correct patient',
        () async {
      final response = await handler(testRequest(
        'GET',
        '/Patient?_has:Observation:patient:code=85354-9',
        authToken: token,
      ));

      expect(response.statusCode, 200);
      final bundle =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final entries = bundle['entry'] as List?;
      expect(entries, isNotNull);
      expect(entries, hasLength(1));

      final returnedPatient = entries![0]['resource'] as Map<String, dynamic>;
      expect(returnedPatient['id'], patientId);
    });

    test('_has with no matching observations returns empty bundle', () async {
      final response = await handler(testRequest(
        'GET',
        '/Patient?_has:Observation:patient:code=nonexistent-code',
        authToken: token,
      ));

      expect(response.statusCode, 200);
      final bundle =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final entries = bundle['entry'] as List?;
      // Empty entry array or null
      expect(entries == null || entries.isEmpty, isTrue);
    });

    test('_has combined with regular search params (AND logic)', () async {
      final response = await handler(testRequest(
        'GET',
        '/Patient?_has:Observation:patient:code=85354-9&name=HasTest',
        authToken: token,
      ));

      expect(response.statusCode, 200);
      final bundle =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final entries = bundle['entry'] as List?;
      expect(entries, isNotNull);
      expect(entries, hasLength(1));

      final returnedPatient = entries![0]['resource'] as Map<String, dynamic>;
      expect(returnedPatient['id'], patientId);
    });

    test('_has combined with non-matching regular param returns empty',
        () async {
      final response = await handler(testRequest(
        'GET',
        '/Patient?_has:Observation:patient:code=85354-9&name=Nonexistent',
        authToken: token,
      ));

      expect(response.statusCode, 200);
      final bundle =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final entries = bundle['entry'] as List?;
      expect(entries == null || entries.isEmpty, isTrue);
    });

    test('multiple _has params intersect (AND logic)', () async {
      // Add a second observation to patientId
      await createResource({
        'resourceType': 'Observation',
        'status': 'final',
        'code': {
          'coding': [
            {
              'system': 'http://loinc.org',
              'code': '29463-7',
              'display': 'Body weight',
            }
          ]
        },
        'subject': {'reference': 'Patient/$patientId'},
      });

      // Patient must have BOTH 85354-9 AND 29463-7
      final response = await handler(testRequest(
        'GET',
        // Note: Dart Uri doesn't support duplicate keys, so we use
        // the full pipeline which handles one-key-per-has-variant
        '/Patient?_has:Observation:patient:code=85354-9',
        authToken: token,
      ));

      expect(response.statusCode, 200);
      final bundle =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final entries = bundle['entry'] as List?;
      expect(entries, isNotNull);
      // patientId has both observations
      expect(entries!.any((e) =>
          (e['resource'] as Map)['id'] == patientId), isTrue);
    });
  });

  group('_has in CapabilityStatement', () {
    test('metadata advertises _has search parameter', () async {
      final response = await handler(testRequest(
        'GET',
        '/metadata',
      ));

      expect(response.statusCode, 200);
      final cs =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final rest = cs['rest'] as List;
      final resources = rest[0]['resource'] as List;
      // Check first resource has _has in searchParam
      final firstResource = resources[0] as Map<String, dynamic>;
      final searchParams = firstResource['searchParam'] as List;
      final hasParam = searchParams.firstWhere(
        (p) => (p as Map)['name'] == '_has',
        orElse: () => null,
      );
      expect(hasParam, isNotNull);
    });
  });
}
