// ignore_for_file: lines_longer_than_80_chars
import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shelf/shelf.dart';

import 'package:fhirant_server/src/handlers/compartment_handler.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

class MockRequest extends Mock implements Request {}

void main() {
  late MockFhirAntDb mockDb;
  late MockRequest mockRequest;

  final testPatient = fhir.Patient(
    id: 'pat-1'.toFhirString,
    name: [fhir.HumanName(family: 'Smith'.toFhirString)],
  );

  final testObservation1 = fhir.Observation(
    id: 'obs-1'.toFhirString,
    status: fhir.ObservationStatus.final_,
    code: fhir.CodeableConcept(
      coding: [fhir.Coding(code: '85354-9'.toFhirCode)],
    ),
    subject: fhir.Reference(reference: 'Patient/pat-1'.toFhirString),
  );

  final testObservation2 = fhir.Observation(
    id: 'obs-2'.toFhirString,
    status: fhir.ObservationStatus.final_,
    code: fhir.CodeableConcept(
      coding: [fhir.Coding(code: '8480-6'.toFhirCode)],
    ),
    subject: fhir.Reference(reference: 'Patient/pat-1'.toFhirString),
  );

  final testEncounter = fhir.Encounter(
    id: 'enc-1'.toFhirString,
    status: fhir.EncounterStatus.finished,
    class_: fhir.Coding(code: 'AMB'.toFhirCode),
  );

  setUpAll(() {
    registerFallbackValue(<String, List<String>>{});
    registerFallbackValue(<String>[]);
    registerFallbackValue(fhir.R4ResourceType.Patient);
  });

  setUp(() {
    mockDb = MockFhirAntDb();
    mockRequest = MockRequest();
  });

  // ─────────────────────────────────────────────────────────────────────────
  // $everything handler
  // ─────────────────────────────────────────────────────────────────────────
  group('everythingHandler', () {
    test('returns 400 for unsupported compartment type', () async {
      when(() => mockRequest.url)
          .thenReturn(Uri.parse('Practitioner/prac-1/\$everything'));

      final response = await everythingHandler(
        mockRequest,
        'Practitioner',
        'prac-1',
        mockDb,
      );

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], equals('OperationOutcome'));
    });

    test('returns 404 when focal resource does not exist', () async {
      when(() => mockRequest.url)
          .thenReturn(Uri.parse('Patient/missing/\$everything'));
      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, 'missing'))
          .thenAnswer((_) async => null);

      final response = await everythingHandler(
        mockRequest,
        'Patient',
        'missing',
        mockDb,
      );

      expect(response.statusCode, equals(404));
    });

    test('returns Bundle with just focal resource when no linked resources',
        () async {
      when(() => mockRequest.url).thenReturn(
          Uri.parse('Patient/pat-1/\$everything'));
      when(() => mockRequest.requestedUri).thenReturn(
          Uri.parse('http://localhost:8080/Patient/pat-1/\$everything'));
      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, 'pat-1'))
          .thenAnswer((_) async => testPatient);
      when(() => mockDb.getCompartmentResourceIds(
            compartmentType: 'Patient',
            compartmentId: 'pat-1',
            compartmentDefinition: any(named: 'compartmentDefinition'),
            typeFilter: any(named: 'typeFilter'),
            since: any(named: 'since'),
          )).thenAnswer((_) async => {});

      final response = await everythingHandler(
        mockRequest,
        'Patient',
        'pat-1',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], equals('Bundle'));
      expect(body['type'], equals('searchset'));
      expect(body['total'], equals(1));
      expect(body['entry'], hasLength(1));
      expect(body['entry'][0]['resource']['resourceType'], equals('Patient'));
    });

    test('returns Bundle with focal + linked resources', () async {
      when(() => mockRequest.url).thenReturn(
          Uri.parse('Patient/pat-1/\$everything'));
      when(() => mockRequest.requestedUri).thenReturn(
          Uri.parse('http://localhost:8080/Patient/pat-1/\$everything'));
      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, 'pat-1'))
          .thenAnswer((_) async => testPatient);
      when(() => mockDb.getResource(fhir.R4ResourceType.Observation, 'obs-1'))
          .thenAnswer((_) async => testObservation1);
      when(() => mockDb.getResource(fhir.R4ResourceType.Observation, 'obs-2'))
          .thenAnswer((_) async => testObservation2);
      when(() => mockDb.getCompartmentResourceIds(
            compartmentType: 'Patient',
            compartmentId: 'pat-1',
            compartmentDefinition: any(named: 'compartmentDefinition'),
            typeFilter: any(named: 'typeFilter'),
            since: any(named: 'since'),
          )).thenAnswer((_) async => {
            'Observation': {'obs-1', 'obs-2'},
          });

      final response = await everythingHandler(
        mockRequest,
        'Patient',
        'pat-1',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['total'], equals(3));
      expect(body['entry'], hasLength(3));
      final types =
          (body['entry'] as List).map((e) => e['resource']['resourceType']).toList();
      expect(types, contains('Patient'));
      expect(types.where((t) => t == 'Observation').length, equals(2));
    });

    test('_type filter limits resource types returned', () async {
      when(() => mockRequest.url).thenReturn(
          Uri.parse('Patient/pat-1/\$everything?_type=Observation'));
      when(() => mockRequest.requestedUri).thenReturn(
          Uri.parse('http://localhost:8080/Patient/pat-1/\$everything?_type=Observation'));
      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, 'pat-1'))
          .thenAnswer((_) async => testPatient);
      when(() => mockDb.getResource(fhir.R4ResourceType.Observation, 'obs-1'))
          .thenAnswer((_) async => testObservation1);
      when(() => mockDb.getCompartmentResourceIds(
            compartmentType: 'Patient',
            compartmentId: 'pat-1',
            compartmentDefinition: any(named: 'compartmentDefinition'),
            typeFilter: ['Observation'],
            since: any(named: 'since'),
          )).thenAnswer((_) async => {
            'Observation': {'obs-1'},
          });

      final response = await everythingHandler(
        mockRequest,
        'Patient',
        'pat-1',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      // Focal + 1 Observation
      expect(body['total'], equals(2));
    });

    test('_since filter passes through to DB query', () async {
      when(() => mockRequest.url).thenReturn(
          Uri.parse('Patient/pat-1/\$everything?_since=2024-01-02'));
      when(() => mockRequest.requestedUri).thenReturn(
          Uri.parse('http://localhost:8080/Patient/pat-1/\$everything?_since=2024-01-02'));
      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, 'pat-1'))
          .thenAnswer((_) async => testPatient);
      when(() => mockDb.getCompartmentResourceIds(
            compartmentType: 'Patient',
            compartmentId: 'pat-1',
            compartmentDefinition: any(named: 'compartmentDefinition'),
            typeFilter: any(named: 'typeFilter'),
            since: DateTime(2024, 1, 2),
          )).thenAnswer((_) async => {});

      final response = await everythingHandler(
        mockRequest,
        'Patient',
        'pat-1',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      verify(() => mockDb.getCompartmentResourceIds(
            compartmentType: 'Patient',
            compartmentId: 'pat-1',
            compartmentDefinition: any(named: 'compartmentDefinition'),
            typeFilter: any(named: 'typeFilter'),
            since: DateTime(2024, 1, 2),
          )).called(1);
    });

    test('_count pagination limits results', () async {
      when(() => mockRequest.url).thenReturn(
          Uri.parse('Patient/pat-1/\$everything?_count=1'));
      when(() => mockRequest.requestedUri).thenReturn(
          Uri.parse('http://localhost:8080/Patient/pat-1/\$everything?_count=1'));
      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, 'pat-1'))
          .thenAnswer((_) async => testPatient);
      when(() => mockDb.getResource(fhir.R4ResourceType.Observation, 'obs-1'))
          .thenAnswer((_) async => testObservation1);
      when(() => mockDb.getResource(fhir.R4ResourceType.Observation, 'obs-2'))
          .thenAnswer((_) async => testObservation2);
      when(() => mockDb.getCompartmentResourceIds(
            compartmentType: 'Patient',
            compartmentId: 'pat-1',
            compartmentDefinition: any(named: 'compartmentDefinition'),
            typeFilter: any(named: 'typeFilter'),
            since: any(named: 'since'),
          )).thenAnswer((_) async => {
            'Observation': {'obs-1', 'obs-2'},
          });

      final response = await everythingHandler(
        mockRequest,
        'Patient',
        'pat-1',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      // Total is still 3, but only 1 entry returned
      expect(body['total'], equals(3));
      expect(body['entry'], hasLength(1));
    });

    test('Encounter \$everything works', () async {
      when(() => mockRequest.url).thenReturn(
          Uri.parse('Encounter/enc-1/\$everything'));
      when(() => mockRequest.requestedUri).thenReturn(
          Uri.parse('http://localhost:8080/Encounter/enc-1/\$everything'));
      when(() => mockDb.getResource(fhir.R4ResourceType.Encounter, 'enc-1'))
          .thenAnswer((_) async => testEncounter);
      when(() => mockDb.getCompartmentResourceIds(
            compartmentType: 'Encounter',
            compartmentId: 'enc-1',
            compartmentDefinition: any(named: 'compartmentDefinition'),
            typeFilter: any(named: 'typeFilter'),
            since: any(named: 'since'),
          )).thenAnswer((_) async => {});

      final response = await everythingHandler(
        mockRequest,
        'Encounter',
        'enc-1',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['total'], equals(1));
      expect(
          body['entry'][0]['resource']['resourceType'], equals('Encounter'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // compartmentSearchHandler
  // ─────────────────────────────────────────────────────────────────────────
  group('compartmentSearchHandler', () {
    test('returns 404 for unsupported compartment type', () async {
      when(() => mockRequest.url)
          .thenReturn(Uri.parse('Practitioner/prac-1/Observation'));

      final response = await compartmentSearchHandler(
        mockRequest,
        'Practitioner',
        'prac-1',
        'Observation',
        mockDb,
      );

      expect(response.statusCode, equals(404));
    });

    test('returns 400 for invalid resource type', () async {
      when(() => mockRequest.url)
          .thenReturn(Uri.parse('Patient/pat-1/FakeType'));

      final response = await compartmentSearchHandler(
        mockRequest,
        'Patient',
        'pat-1',
        'FakeType',
        mockDb,
      );

      expect(response.statusCode, equals(400));
    });

    test('returns 400 for resource type not in compartment', () async {
      when(() => mockRequest.url)
          .thenReturn(Uri.parse('Patient/pat-1/StructureDefinition'));

      final response = await compartmentSearchHandler(
        mockRequest,
        'Patient',
        'pat-1',
        'StructureDefinition',
        mockDb,
      );

      expect(response.statusCode, equals(400));
    });

    test('returns 404 when focal resource does not exist', () async {
      when(() => mockRequest.url)
          .thenReturn(Uri.parse('Patient/missing/Observation'));
      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, 'missing'))
          .thenAnswer((_) async => null);

      final response = await compartmentSearchHandler(
        mockRequest,
        'Patient',
        'missing',
        'Observation',
        mockDb,
      );

      expect(response.statusCode, equals(404));
    });

    test('returns filtered resources for compartment type', () async {
      when(() => mockRequest.url).thenReturn(
          Uri.parse('Patient/pat-1/Observation'));
      when(() => mockRequest.requestedUri).thenReturn(
          Uri.parse('http://localhost:8080/Patient/pat-1/Observation'));
      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, 'pat-1'))
          .thenAnswer((_) async => testPatient);
      when(() => mockDb.getResource(fhir.R4ResourceType.Observation, 'obs-1'))
          .thenAnswer((_) async => testObservation1);
      when(() => mockDb.getResource(fhir.R4ResourceType.Observation, 'obs-2'))
          .thenAnswer((_) async => testObservation2);
      when(() => mockDb.getCompartmentResourceIds(
            compartmentType: 'Patient',
            compartmentId: 'pat-1',
            compartmentDefinition: any(named: 'compartmentDefinition'),
            typeFilter: any(named: 'typeFilter'),
            since: any(named: 'since'),
          )).thenAnswer((_) async => {
            'Observation': {'obs-1', 'obs-2'},
          });

      final response = await compartmentSearchHandler(
        mockRequest,
        'Patient',
        'pat-1',
        'Observation',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], equals('Bundle'));
      expect(body['type'], equals('searchset'));
      expect(body['entry'], hasLength(2));
    });

    test('combines compartment with additional search params', () async {
      when(() => mockRequest.url).thenReturn(
          Uri.parse('Patient/pat-1/Observation?code=85354-9'));
      when(() => mockRequest.requestedUri).thenReturn(
          Uri.parse('http://localhost:8080/Patient/pat-1/Observation?code=85354-9'));
      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, 'pat-1'))
          .thenAnswer((_) async => testPatient);
      when(() => mockDb.getCompartmentResourceIds(
            compartmentType: 'Patient',
            compartmentId: 'pat-1',
            compartmentDefinition: any(named: 'compartmentDefinition'),
            typeFilter: any(named: 'typeFilter'),
            since: any(named: 'since'),
          )).thenAnswer((_) async => {
            'Observation': {'obs-1', 'obs-2'},
          });
      // search() called with _id constraint + code filter
      when(() => mockDb.search(
            resourceType: fhir.R4ResourceType.Observation,
            searchParameters: any(named: 'searchParameters'),
            count: any(named: 'count'),
            offset: any(named: 'offset'),
            sort: any(named: 'sort'),
          )).thenAnswer((_) async => [testObservation1]);

      final response = await compartmentSearchHandler(
        mockRequest,
        'Patient',
        'pat-1',
        'Observation',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['entry'], hasLength(1));
      expect(body['entry'][0]['resource']['id'], equals('obs-1'));

      // Verify search was called with _id constraint
      final captured = verify(() => mockDb.search(
            resourceType: fhir.R4ResourceType.Observation,
            searchParameters: captureAny(named: 'searchParameters'),
            count: any(named: 'count'),
            offset: any(named: 'offset'),
            sort: any(named: 'sort'),
          )).captured;
      final searchParams = captured.first as Map<String, List<String>>;
      expect(searchParams.containsKey('_id'), isTrue);
      expect(searchParams['_id'], containsAll(['obs-1', 'obs-2']));
      expect(searchParams.containsKey('code'), isTrue);
    });

    test('returns empty Bundle when no compartment resources found', () async {
      when(() => mockRequest.url).thenReturn(
          Uri.parse('Patient/pat-1/Condition'));
      when(() => mockRequest.requestedUri).thenReturn(
          Uri.parse('http://localhost:8080/Patient/pat-1/Condition'));
      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, 'pat-1'))
          .thenAnswer((_) async => testPatient);
      when(() => mockDb.getCompartmentResourceIds(
            compartmentType: 'Patient',
            compartmentId: 'pat-1',
            compartmentDefinition: any(named: 'compartmentDefinition'),
            typeFilter: any(named: 'typeFilter'),
            since: any(named: 'since'),
          )).thenAnswer((_) async => {});

      final response = await compartmentSearchHandler(
        mockRequest,
        'Patient',
        'pat-1',
        'Condition',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['entry'], isEmpty);
      expect(body['total'], equals(0));
    });
  });
}
