import 'dart:convert';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:fhirant_server/src/handlers/document_handler.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

class MockRequest extends Mock implements Request {}

void main() {
  setUpAll(() {
    registerFallbackValue(fhir.R4ResourceType.Patient);
  });

  group('documentHandler', () {
    late MockFhirAntDb mockDb;
    late MockRequest mockRequest;

    setUp(() {
      mockDb = MockFhirAntDb();
      mockRequest = MockRequest();
      when(() => mockRequest.requestedUri)
          .thenReturn(Uri.parse('http://localhost:8080/Composition/comp1/\$document'));
    });

    test('returns 404 when Composition not found', () async {
      when(() => mockDb.getResource(fhir.R4ResourceType.Composition, 'comp1'))
          .thenAnswer((_) async => null);

      final response = await documentHandler(mockRequest, 'comp1', mockDb);
      expect(response.statusCode, 404);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['resourceType'], 'OperationOutcome');
    });

    test('returns document Bundle with Composition as first entry', () async {
      final composition = fhir.Composition.fromJson({
        'resourceType': 'Composition',
        'id': 'comp1',
        'status': 'final',
        'type': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '11503-0'}
          ]
        },
        'date': '2024-01-01',
        'title': 'Test Document',
        'author': [
          {'reference': 'Practitioner/prac1'}
        ],
        'subject': {'reference': 'Patient/pat1'},
      });

      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'pat1',
        'name': [
          {'family': 'Smith'}
        ],
      });

      final practitioner = fhir.Practitioner.fromJson({
        'resourceType': 'Practitioner',
        'id': 'prac1',
        'name': [
          {'family': 'Jones'}
        ],
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.Composition, 'comp1'))
          .thenAnswer((_) async => composition);
      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, 'pat1'))
          .thenAnswer((_) async => patient);
      when(() => mockDb.getResource(fhir.R4ResourceType.Practitioner, 'prac1'))
          .thenAnswer((_) async => practitioner);

      final response = await documentHandler(mockRequest, 'comp1', mockDb);
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['resourceType'], 'Bundle');
      expect(body['type'], 'document');
      expect(body['timestamp'], isNotNull);

      final entries = body['entry'] as List;
      expect(entries.length, 3);

      // First entry is always the Composition
      expect(entries[0]['resource']['resourceType'], 'Composition');
      expect(entries[0]['resource']['id'], 'comp1');

      // Second entry is the subject
      expect(entries[1]['resource']['resourceType'], 'Patient');
      expect(entries[1]['resource']['id'], 'pat1');

      // Third entry is the author
      expect(entries[2]['resource']['resourceType'], 'Practitioner');
      expect(entries[2]['resource']['id'], 'prac1');
    });

    test('includes fullUrl on all entries', () async {
      final composition = fhir.Composition.fromJson({
        'resourceType': 'Composition',
        'id': 'comp1',
        'status': 'final',
        'type': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '11503-0'}
          ]
        },
        'date': '2024-01-01',
        'title': 'Test Document',
        'author': [
          {'reference': 'Practitioner/prac1'}
        ],
      });

      final practitioner = fhir.Practitioner.fromJson({
        'resourceType': 'Practitioner',
        'id': 'prac1',
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.Composition, 'comp1'))
          .thenAnswer((_) async => composition);
      when(() => mockDb.getResource(fhir.R4ResourceType.Practitioner, 'prac1'))
          .thenAnswer((_) async => practitioner);

      final response = await documentHandler(mockRequest, 'comp1', mockDb);
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString()) as Map;
      final entries = body['entry'] as List;
      for (final entry in entries) {
        expect(entry['fullUrl'], isNotNull);
        expect(entry['fullUrl'], startsWith('http://localhost:8080/'));
      }
    });

    test('handles Composition with sections and nested references', () async {
      final composition = fhir.Composition.fromJson({
        'resourceType': 'Composition',
        'id': 'comp1',
        'status': 'final',
        'type': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '11503-0'}
          ]
        },
        'date': '2024-01-01',
        'title': 'Test Document',
        'author': [
          {'reference': 'Practitioner/prac1'}
        ],
        'subject': {'reference': 'Patient/pat1'},
        'section': [
          {
            'title': 'Problems',
            'entry': [
              {'reference': 'Condition/cond1'},
              {'reference': 'Condition/cond2'},
            ],
          },
          {
            'title': 'Medications',
            'entry': [
              {'reference': 'MedicationRequest/med1'},
            ],
          },
        ],
      });

      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'pat1',
      });
      final practitioner = fhir.Practitioner.fromJson({
        'resourceType': 'Practitioner',
        'id': 'prac1',
      });
      final condition1 = fhir.Condition.fromJson({
        'resourceType': 'Condition',
        'id': 'cond1',
        'subject': {'reference': 'Patient/pat1'},
      });
      final condition2 = fhir.Condition.fromJson({
        'resourceType': 'Condition',
        'id': 'cond2',
        'subject': {'reference': 'Patient/pat1'},
      });
      final medRequest = fhir.MedicationRequest.fromJson({
        'resourceType': 'MedicationRequest',
        'id': 'med1',
        'status': 'active',
        'intent': 'order',
        'subject': {'reference': 'Patient/pat1'},
        'medicationCodeableConcept': {
          'text': 'Aspirin',
        },
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.Composition, 'comp1'))
          .thenAnswer((_) async => composition);
      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, 'pat1'))
          .thenAnswer((_) async => patient);
      when(() => mockDb.getResource(fhir.R4ResourceType.Practitioner, 'prac1'))
          .thenAnswer((_) async => practitioner);
      when(() => mockDb.getResource(fhir.R4ResourceType.Condition, 'cond1'))
          .thenAnswer((_) async => condition1);
      when(() => mockDb.getResource(fhir.R4ResourceType.Condition, 'cond2'))
          .thenAnswer((_) async => condition2);
      when(() =>
              mockDb.getResource(fhir.R4ResourceType.MedicationRequest, 'med1'))
          .thenAnswer((_) async => medRequest);

      final response = await documentHandler(mockRequest, 'comp1', mockDb);
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString()) as Map;
      final entries = body['entry'] as List;
      // Composition + Patient + Practitioner + 2 Conditions + MedicationRequest = 6
      expect(entries.length, 6);

      // First is Composition
      expect(entries[0]['resource']['resourceType'], 'Composition');
      // Second is subject (Patient)
      expect(entries[1]['resource']['resourceType'], 'Patient');
    });

    test('deduplicates references', () async {
      // Composition references Patient both as subject and in section entry
      final composition = fhir.Composition.fromJson({
        'resourceType': 'Composition',
        'id': 'comp1',
        'status': 'final',
        'type': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '11503-0'}
          ]
        },
        'date': '2024-01-01',
        'title': 'Test Document',
        'author': [
          {'reference': 'Practitioner/prac1'}
        ],
        'subject': {'reference': 'Patient/pat1'},
        'section': [
          {
            'title': 'Demographics',
            'entry': [
              {'reference': 'Patient/pat1'},
            ],
          },
        ],
      });

      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'pat1',
      });
      final practitioner = fhir.Practitioner.fromJson({
        'resourceType': 'Practitioner',
        'id': 'prac1',
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.Composition, 'comp1'))
          .thenAnswer((_) async => composition);
      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, 'pat1'))
          .thenAnswer((_) async => patient);
      when(() => mockDb.getResource(fhir.R4ResourceType.Practitioner, 'prac1'))
          .thenAnswer((_) async => practitioner);

      final response = await documentHandler(mockRequest, 'comp1', mockDb);
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString()) as Map;
      final entries = body['entry'] as List;
      // Patient appears only once despite being referenced twice
      // Composition + Patient + Practitioner = 3
      expect(entries.length, 3);
    });

    test('handles unresolvable references gracefully', () async {
      final composition = fhir.Composition.fromJson({
        'resourceType': 'Composition',
        'id': 'comp1',
        'status': 'final',
        'type': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '11503-0'}
          ]
        },
        'date': '2024-01-01',
        'title': 'Test Document',
        'author': [
          {'reference': 'Practitioner/prac1'}
        ],
        'subject': {'reference': 'Patient/nonexistent'},
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.Composition, 'comp1'))
          .thenAnswer((_) async => composition);
      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, 'nonexistent'))
          .thenAnswer((_) async => null);
      when(() => mockDb.getResource(fhir.R4ResourceType.Practitioner, 'prac1'))
          .thenAnswer((_) async => null);

      final response = await documentHandler(mockRequest, 'comp1', mockDb);
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString()) as Map;
      final entries = body['entry'] as List;
      // Only the Composition itself (unresolvable refs skipped)
      expect(entries.length, 1);
      expect(entries[0]['resource']['resourceType'], 'Composition');
    });

    test('includes custodian and attester references', () async {
      final composition = fhir.Composition.fromJson({
        'resourceType': 'Composition',
        'id': 'comp1',
        'status': 'final',
        'type': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '11503-0'}
          ]
        },
        'date': '2024-01-01',
        'title': 'Test Document',
        'author': [
          {'reference': 'Practitioner/prac1'}
        ],
        'custodian': {'reference': 'Organization/org1'},
        'attester': [
          {
            'mode': 'legal',
            'party': {'reference': 'Practitioner/prac2'},
          }
        ],
      });

      final practitioner1 = fhir.Practitioner.fromJson({
        'resourceType': 'Practitioner',
        'id': 'prac1',
      });
      final practitioner2 = fhir.Practitioner.fromJson({
        'resourceType': 'Practitioner',
        'id': 'prac2',
      });
      final organization = fhir.Organization.fromJson({
        'resourceType': 'Organization',
        'id': 'org1',
        'name': 'Test Org',
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.Composition, 'comp1'))
          .thenAnswer((_) async => composition);
      when(() => mockDb.getResource(fhir.R4ResourceType.Practitioner, 'prac1'))
          .thenAnswer((_) async => practitioner1);
      when(() => mockDb.getResource(fhir.R4ResourceType.Practitioner, 'prac2'))
          .thenAnswer((_) async => practitioner2);
      when(() => mockDb.getResource(fhir.R4ResourceType.Organization, 'org1'))
          .thenAnswer((_) async => organization);

      final response = await documentHandler(mockRequest, 'comp1', mockDb);
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString()) as Map;
      final entries = body['entry'] as List;
      // Composition + 2 Practitioners + Organization = 4
      expect(entries.length, 4);

      final types =
          entries.map((e) => e['resource']['resourceType'] as String).toList();
      expect(types, contains('Organization'));
      expect(types.where((t) => t == 'Practitioner').length, 2);
    });

    test('handles Composition with encounter reference', () async {
      final composition = fhir.Composition.fromJson({
        'resourceType': 'Composition',
        'id': 'comp1',
        'status': 'final',
        'type': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '11503-0'}
          ]
        },
        'date': '2024-01-01',
        'title': 'Test Document',
        'author': [
          {'reference': 'Practitioner/prac1'}
        ],
        'encounter': {'reference': 'Encounter/enc1'},
      });

      final practitioner = fhir.Practitioner.fromJson({
        'resourceType': 'Practitioner',
        'id': 'prac1',
      });
      final encounter = fhir.Encounter.fromJson({
        'resourceType': 'Encounter',
        'id': 'enc1',
        'status': 'finished',
        'class': {
          'system': 'http://terminology.hl7.org/CodeSystem/v3-ActCode',
          'code': 'AMB',
        },
      });

      when(() => mockDb.getResource(fhir.R4ResourceType.Composition, 'comp1'))
          .thenAnswer((_) async => composition);
      when(() => mockDb.getResource(fhir.R4ResourceType.Practitioner, 'prac1'))
          .thenAnswer((_) async => practitioner);
      when(() => mockDb.getResource(fhir.R4ResourceType.Encounter, 'enc1'))
          .thenAnswer((_) async => encounter);

      final response = await documentHandler(mockRequest, 'comp1', mockDb);
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString()) as Map;
      final entries = body['entry'] as List;
      // Composition + Practitioner + Encounter = 3
      expect(entries.length, 3);

      final types =
          entries.map((e) => e['resource']['resourceType'] as String).toList();
      expect(types, contains('Encounter'));
    });
  });
}
