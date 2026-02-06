import 'package:flutter_test/flutter_test.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:drift/native.dart';

void main() {
  late FhirAntDb db;

  setUp(() async {
    db = FhirAntDb.forTesting(NativeDatabase.memory());
    await db.initialize();
  });

  tearDown(() async {
    await db.close();
  });

  // ── Test fixtures ──────────────────────────────────────────────────────

  // Patient 1: Smith, male, born 1990-01-15
  fhir.Patient buildPatient1() => fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'pt-1',
        'name': [
          {
            'family': 'Smith',
            'given': ['John'],
          }
        ],
        'gender': 'male',
        'birthDate': '1990-01-15',
        'identifier': [
          {'system': 'http://hospital.org/mrn', 'value': 'MRN001'}
        ],
        'address': [
          {'city': 'Boston', 'state': 'MA'}
        ],
        'active': true,
      });

  // Patient 2: Smith, female, born 1985-06-20
  fhir.Patient buildPatient2() => fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'pt-2',
        'name': [
          {
            'family': 'Smith',
            'given': ['Jane'],
          }
        ],
        'gender': 'female',
        'birthDate': '1985-06-20',
        'active': true,
      });

  // Patient 3: Jones, male, born 2000-03-10
  fhir.Patient buildPatient3() => fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'pt-3',
        'name': [
          {
            'family': 'Jones',
            'given': ['Bob'],
          }
        ],
        'gender': 'male',
        'birthDate': '2000-03-10',
      });

  // Observation referencing patient1
  fhir.Observation buildObs1() => fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': 'obs-1',
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '12345-6'}
          ]
        },
        'subject': {'reference': 'Patient/pt-1'},
      });

  /// Helper to save all four fixtures and return them.
  Future<void> seedAll() async {
    await db.saveResource(buildPatient1());
    await db.saveResource(buildPatient2());
    await db.saveResource(buildPatient3());
    await db.saveResource(buildObs1());
  }

  /// Extract sorted IDs from a list of resources.
  List<String> ids(List<fhir.Resource> results) {
    final list = results
        .map((r) => r.id?.valueString ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    list.sort();
    return list;
  }

  // ── String search ─────────────────────────────────────────────────────

  group('String search', () {
    test('search by name finds matching patients', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'name': ['Smith'],
        },
      );

      expect(ids(results), containsAll(['pt-1', 'pt-2']));
      expect(results.length, 2);
    });

    test('search by family name finds match', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'family': ['Jones'],
        },
      );

      expect(ids(results), equals(['pt-3']));
    });

    test('search by name is case-insensitive', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'name': ['smith'],
        },
      );

      expect(ids(results), containsAll(['pt-1', 'pt-2']));
      expect(results.length, 2);
    });

    test('search by name returns empty for non-matching', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'name': ['NonExistent'],
        },
      );

      expect(results, isEmpty);
    });

    test('search with multiple values uses OR logic', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'name': ['Smith', 'Jones'],
        },
      );

      expect(ids(results), containsAll(['pt-1', 'pt-2', 'pt-3']));
      expect(results.length, 3);
    });
  });

  // ── Token search ──────────────────────────────────────────────────────

  group('Token search', () {
    test('search by gender token', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'gender': ['male'],
        },
      );

      expect(ids(results), containsAll(['pt-1', 'pt-3']));
      expect(results.length, 2);
    });

    test('search by identifier with system|value', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'identifier': ['http://hospital.org/mrn|MRN001'],
        },
      );

      expect(ids(results), equals(['pt-1']));
    });

    test('search by active boolean token', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'active': ['true'],
        },
      );

      expect(ids(results), containsAll(['pt-1', 'pt-2']));
      expect(results.length, 2);
    });
  });

  // ── Date search ───────────────────────────────────────────────────────

  group('Date search', () {
    test('search by birthDate exact match', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'birthdate': ['1990-01-15'],
        },
      );

      expect(ids(results), equals(['pt-1']));
    });

    test('search by birthDate with gt modifier', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'birthdate': ['1995-01-01:gt'],
        },
      );

      expect(ids(results), equals(['pt-3']));
    });
  });

  // ── Reference search ──────────────────────────────────────────────────

  group('Reference search', () {
    test('search Observation by subject reference', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Observation,
        searchParameters: {
          'subject': ['Patient/pt-1'],
        },
      );

      expect(ids(results), equals(['obs-1']));
    });
  });

  // ── Special parameters ────────────────────────────────────────────────

  group('Special parameters', () {
    test('search by _id', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          '_id': ['pt-1'],
        },
      );

      expect(ids(results), equals(['pt-1']));
    });

    test('search by _id with multiple IDs (OR)', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          '_id': ['pt-1,pt-2'],
        },
      );

      expect(ids(results), containsAll(['pt-1', 'pt-2']));
      expect(results.length, 2);
    });
  });

  // ── AND logic ─────────────────────────────────────────────────────────

  group('AND logic', () {
    test('search with multiple params uses AND logic', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'gender': ['male'],
          'name': ['Smith'],
        },
      );

      expect(ids(results), equals(['pt-1']));
    });
  });

  // ── Search count ──────────────────────────────────────────────────────

  group('Search count', () {
    test('searchCount returns correct count for filtered search', () async {
      await seedAll();

      final count = await db.searchCount(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'gender': ['male'],
        },
      );

      expect(count, 2);
    });

    test('searchCount with empty params returns total', () async {
      await seedAll();

      final count = await db.searchCount(
        resourceType: fhir.R4ResourceType.Patient,
      );

      expect(count, 3);
    });
  });

  // ── Sorting / pagination ──────────────────────────────────────────────

  group('Sorting and pagination', () {
    test('search with sort by _lastUpdated ascending', () async {
      await db.saveResource(buildPatient1());
      await Future.delayed(const Duration(milliseconds: 50));
      await db.saveResource(buildPatient2());
      await Future.delayed(const Duration(milliseconds: 50));
      await db.saveResource(buildPatient3());

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        sort: ['_lastUpdated'],
      );

      expect(results.length, 3);
      final resultIds = results.map((r) => r.id?.valueString).toList();
      expect(resultIds, equals(['pt-1', 'pt-2', 'pt-3']));
    });

    test('search with sort descending', () async {
      await db.saveResource(buildPatient1());
      await Future.delayed(const Duration(milliseconds: 50));
      await db.saveResource(buildPatient2());
      await Future.delayed(const Duration(milliseconds: 50));
      await db.saveResource(buildPatient3());

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        sort: ['-_lastUpdated'],
      );

      expect(results.length, 3);
      final resultIds = results.map((r) => r.id?.valueString).toList();
      expect(resultIds, equals(['pt-3', 'pt-2', 'pt-1']));
    });

    test('search with count and offset pagination', () async {
      await db.saveResource(buildPatient1());
      await Future.delayed(const Duration(milliseconds: 50));
      await db.saveResource(buildPatient2());
      await Future.delayed(const Duration(milliseconds: 50));
      await db.saveResource(buildPatient3());

      final firstPage = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        count: 2,
        offset: 0,
      );
      expect(firstPage.length, 2);

      final secondPage = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        count: 2,
        offset: 2,
      );
      expect(secondPage.length, 1);
    });
  });
}
