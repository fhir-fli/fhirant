import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'package:fhirant_server/src/handlers/backup_handler.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

void main() {
  late MockFhirAntDb mockDb;

  setUpAll(() {
    registerFallbackValue(fhir.Patient());
  });

  setUp(() {
    mockDb = MockFhirAntDb();
  });

  group('backupHandler', () {
    test('returns a collection Bundle with resources', () async {
      final patient = fhir.Patient(
        id: 'p1'.toFhirString,
        name: [fhir.HumanName(family: 'Smith'.toFhirString)],
      );
      final observation = fhir.Observation(
        id: 'o1'.toFhirString,
        status: fhir.ObservationStatus.final_,
        code: fhir.CodeableConcept(
          text: 'Test'.toFhirString,
        ),
      );

      when(() => mockDb.getResourceTypes()).thenAnswer(
        (_) async => [
          fhir.R4ResourceType.Patient,
          fhir.R4ResourceType.Observation,
        ],
      );
      when(() => mockDb.getResourcesByType(fhir.R4ResourceType.Patient))
          .thenAnswer((_) async => [patient]);
      when(() => mockDb.getResourcesByType(fhir.R4ResourceType.Observation))
          .thenAnswer((_) async => [observation]);

      final request =
          Request('POST', Uri.parse('http://localhost:8080/\$backup'));
      final response = await backupHandler(request, mockDb);

      expect(response.statusCode, equals(200));
      expect(response.headers['content-type'], equals('application/fhir+json'));

      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['resourceType'], equals('Bundle'));
      expect(body['type'], equals('collection'));
      expect(body['total'], equals(2));

      final entries = body['entry'] as List;
      expect(entries, hasLength(2));

      // Verify entries contain the resources
      final entryTypes = entries
          .map((e) => (e as Map<String, dynamic>)['resource']['resourceType'])
          .toList();
      expect(entryTypes, contains('Patient'));
      expect(entryTypes, contains('Observation'));

      // Verify fullUrl is set
      final fullUrls =
          entries.map((e) => (e as Map<String, dynamic>)['fullUrl']).toList();
      expect(fullUrls, contains('Patient/p1'));
      expect(fullUrls, contains('Observation/o1'));
    });

    test('returns empty Bundle when DB has no resources', () async {
      when(() => mockDb.getResourceTypes()).thenAnswer((_) async => []);

      final request =
          Request('POST', Uri.parse('http://localhost:8080/\$backup'));
      final response = await backupHandler(request, mockDb);

      expect(response.statusCode, equals(200));

      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['resourceType'], equals('Bundle'));
      expect(body['type'], equals('collection'));
      expect(body['total'], equals(0));
      expect(body.containsKey('entry'), isFalse);
    });

    test('returns 500 when DB throws', () async {
      when(() => mockDb.getResourceTypes())
          .thenThrow(Exception('DB connection lost'));

      final request =
          Request('POST', Uri.parse('http://localhost:8080/\$backup'));
      final response = await backupHandler(request, mockDb);

      expect(response.statusCode, equals(500));

      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['resourceType'], equals('OperationOutcome'));
    });
  });

  group('restoreHandler', () {
    test('saves resources and returns OperationOutcome', () async {
      final patient = fhir.Patient(
        id: 'p1'.toFhirString,
        name: [fhir.HumanName(family: 'Smith'.toFhirString)],
      );
      final observation = fhir.Observation(
        id: 'o1'.toFhirString,
        status: fhir.ObservationStatus.final_,
        code: fhir.CodeableConcept(
          text: 'Test'.toFhirString,
        ),
      );

      final bundle = fhir.Bundle(
        type: fhir.BundleType.collection,
        entry: [
          fhir.BundleEntry(resource: patient),
          fhir.BundleEntry(resource: observation),
        ],
      );

      when(() => mockDb.saveResource(any())).thenAnswer((_) async => true);

      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/\$restore'),
        body: jsonEncode(bundle.toJson()),
        headers: {'content-type': 'application/fhir+json'},
      );
      final response = await restoreHandler(request, mockDb);

      expect(response.statusCode, equals(200));
      expect(response.headers['content-type'], equals('application/fhir+json'));

      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['resourceType'], equals('OperationOutcome'));

      final issues = body['issue'] as List;
      // First issue is the summary
      final summary = issues[0] as Map<String, dynamic>;
      expect(summary['diagnostics'], contains('2 saved'));
      expect(summary['diagnostics'], contains('0 errors'));

      // Verify saveResource was called twice
      verify(() => mockDb.saveResource(any())).called(2);
    });

    test('returns 400 for empty body', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/\$restore'),
        body: '',
        headers: {'content-type': 'application/fhir+json'},
      );
      final response = await restoreHandler(request, mockDb);

      expect(response.statusCode, equals(400));

      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['resourceType'], equals('OperationOutcome'));
      expect((body['issue'] as List)[0]['diagnostics'],
          contains('empty'));
    });

    test('returns 400 for invalid JSON', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/\$restore'),
        body: 'not-json{{{',
        headers: {'content-type': 'application/fhir+json'},
      );
      final response = await restoreHandler(request, mockDb);

      expect(response.statusCode, equals(400));

      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['resourceType'], equals('OperationOutcome'));
      expect((body['issue'] as List)[0]['diagnostics'],
          contains('Invalid JSON'));
    });

    test('returns 400 for non-Bundle resource', () async {
      final patient = fhir.Patient(id: 'p1'.toFhirString);

      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/\$restore'),
        body: jsonEncode(patient.toJson()),
        headers: {'content-type': 'application/fhir+json'},
      );
      final response = await restoreHandler(request, mockDb);

      expect(response.statusCode, equals(400));

      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['resourceType'], equals('OperationOutcome'));
      expect((body['issue'] as List)[0]['diagnostics'],
          contains('Expected a Bundle'));
    });

    test('reports errors for entries that fail to save', () async {
      final patient1 = fhir.Patient(id: 'p1'.toFhirString);
      final patient2 = fhir.Patient(id: 'p2'.toFhirString);

      final bundle = fhir.Bundle(
        type: fhir.BundleType.collection,
        entry: [
          fhir.BundleEntry(resource: patient1),
          fhir.BundleEntry(resource: patient2),
        ],
      );

      // First save succeeds, second fails
      var callCount = 0;
      when(() => mockDb.saveResource(any())).thenAnswer((_) async {
        callCount++;
        return callCount == 1;
      });

      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/\$restore'),
        body: jsonEncode(bundle.toJson()),
        headers: {'content-type': 'application/fhir+json'},
      );
      final response = await restoreHandler(request, mockDb);

      expect(response.statusCode, equals(200));

      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final issues = body['issue'] as List;
      final summary = issues[0] as Map<String, dynamic>;
      expect(summary['diagnostics'], contains('1 saved'));
      expect(summary['diagnostics'], contains('1 errors'));
    });

    test('handles entries without resource gracefully', () async {
      final bundle = fhir.Bundle(
        type: fhir.BundleType.collection,
        entry: [
          fhir.BundleEntry(
            fullUrl: 'urn:uuid:test'.toFhirUri,
          ),
        ],
      );

      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/\$restore'),
        body: jsonEncode(bundle.toJson()),
        headers: {'content-type': 'application/fhir+json'},
      );
      final response = await restoreHandler(request, mockDb);

      expect(response.statusCode, equals(200));

      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final issues = body['issue'] as List;
      final summary = issues[0] as Map<String, dynamic>;
      expect(summary['diagnostics'], contains('0 saved'));
      expect(summary['diagnostics'], contains('1 errors'));
    });
  });
}
