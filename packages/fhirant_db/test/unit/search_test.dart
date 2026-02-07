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

  // ── URI search ──────────────────────────────────────────────────────

  group('URI search', () {
    fhir.ValueSet buildValueSet1() => fhir.ValueSet.fromJson({
          'resourceType': 'ValueSet',
          'id': 'vs-1',
          'url': 'http://example.org/fhir/ValueSet/my-codes',
          'status': 'active',
        });

    fhir.ValueSet buildValueSet2() => fhir.ValueSet.fromJson({
          'resourceType': 'ValueSet',
          'id': 'vs-2',
          'url': 'http://example.org/fhir/ValueSet/other-codes',
          'status': 'active',
        });

    fhir.ValueSet buildValueSet3() => fhir.ValueSet.fromJson({
          'resourceType': 'ValueSet',
          'id': 'vs-3',
          'url': 'http://different.org/fhir/ValueSet/different',
          'status': 'active',
        });

    Future<void> seedValueSets() async {
      await db.saveResource(buildValueSet1());
      await db.saveResource(buildValueSet2());
      await db.saveResource(buildValueSet3());
    }

    test('exact URL match finds one ValueSet', () async {
      await seedValueSets();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.ValueSet,
        searchParameters: {
          'url': ['http://example.org/fhir/ValueSet/my-codes'],
        },
      );

      expect(ids(results), equals(['vs-1']));
    });

    test('non-matching URL returns empty', () async {
      await seedValueSets();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.ValueSet,
        searchParameters: {
          'url': ['http://nonexistent.org/fhir/ValueSet/none'],
        },
      );

      expect(results, isEmpty);
    });

    test(':above modifier prefix match finds multiple', () async {
      await seedValueSets();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.ValueSet,
        searchParameters: {
          'url': ['http://example.org/fhir/ValueSet:above'],
        },
      );

      expect(ids(results), containsAll(['vs-1', 'vs-2']));
      expect(results.length, 2);
    });

    test('OR logic with multiple URLs finds multiple', () async {
      await seedValueSets();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.ValueSet,
        searchParameters: {
          'url': [
            'http://example.org/fhir/ValueSet/my-codes',
            'http://different.org/fhir/ValueSet/different',
          ],
        },
      );

      expect(ids(results), containsAll(['vs-1', 'vs-3']));
      expect(results.length, 2);
    });
  });

  // ── Quantity search ─────────────────────────────────────────────────

  group('Quantity search', () {
    // ChargeItem.quantity is indexed as quantity search parameter
    fhir.ChargeItem buildChargeItem1() => fhir.ChargeItem.fromJson({
          'resourceType': 'ChargeItem',
          'id': 'ci-1',
          'status': 'billable',
          'code': {
            'coding': [
              {'system': 'http://example.org', 'code': 'item-a'}
            ]
          },
          'subject': {'reference': 'Patient/pt-1'},
          'quantity': {
            'value': 5.0,
            'unit': 'mg',
            'system': 'http://unitsofmeasure.org',
            'code': 'mg',
          },
        });

    fhir.ChargeItem buildChargeItem2() => fhir.ChargeItem.fromJson({
          'resourceType': 'ChargeItem',
          'id': 'ci-2',
          'status': 'billable',
          'code': {
            'coding': [
              {'system': 'http://example.org', 'code': 'item-b'}
            ]
          },
          'subject': {'reference': 'Patient/pt-1'},
          'quantity': {
            'value': 10.0,
            'unit': 'mL',
            'system': 'http://unitsofmeasure.org',
            'code': 'mL',
          },
        });

    fhir.ChargeItem buildChargeItem3() => fhir.ChargeItem.fromJson({
          'resourceType': 'ChargeItem',
          'id': 'ci-3',
          'status': 'billable',
          'code': {
            'coding': [
              {'system': 'http://example.org', 'code': 'item-c'}
            ]
          },
          'subject': {'reference': 'Patient/pt-1'},
          'quantity': {
            'value': 5.0,
            'unit': 'mL',
            'system': 'http://unitsofmeasure.org',
            'code': 'mL',
          },
        });

    Future<void> seedChargeItems() async {
      await db.saveResource(buildChargeItem1());
      await db.saveResource(buildChargeItem2());
      await db.saveResource(buildChargeItem3());
    }

    test('value-only match finds ChargeItems with that quantity', () async {
      await seedChargeItems();

      // param name 'quantity' matches stored path 'ChargeItem.quantity'
      final results = await db.search(
        resourceType: fhir.R4ResourceType.ChargeItem,
        searchParameters: {
          'quantity': ['5'],
        },
      );

      expect(ids(results), containsAll(['ci-1', 'ci-3']));
      expect(results.length, 2);
    });

    test('gt modifier finds ChargeItems above threshold', () async {
      await seedChargeItems();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.ChargeItem,
        searchParameters: {
          'quantity': ['7:gt'],
        },
      );

      expect(ids(results), equals(['ci-2']));
    });

    test('value|unit filters by unit', () async {
      await seedChargeItems();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.ChargeItem,
        searchParameters: {
          'quantity': ['5|mg'],
        },
      );

      expect(ids(results), equals(['ci-1']));
    });

    test('system|value|unit format narrows results', () async {
      await seedChargeItems();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.ChargeItem,
        searchParameters: {
          'quantity': ['http://unitsofmeasure.org|5|mL'],
        },
      );

      expect(ids(results), equals(['ci-3']));
    });
  });

  // ── Number search ───────────────────────────────────────────────────

  group('Number search', () {
    fhir.RiskAssessment buildRisk1() => fhir.RiskAssessment.fromJson({
          'resourceType': 'RiskAssessment',
          'id': 'risk-1',
          'status': 'final',
          'subject': {'reference': 'Patient/pt-1'},
          'prediction': [
            {
              'probabilityDecimal': 0.75,
            }
          ],
        });

    fhir.RiskAssessment buildRisk2() => fhir.RiskAssessment.fromJson({
          'resourceType': 'RiskAssessment',
          'id': 'risk-2',
          'status': 'final',
          'subject': {'reference': 'Patient/pt-2'},
          'prediction': [
            {
              'probabilityDecimal': 0.25,
            }
          ],
        });

    Future<void> seedRisks() async {
      await db.saveResource(buildRisk1());
      await db.saveResource(buildRisk2());
    }

    test('exact number match finds resource', () async {
      await seedRisks();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.RiskAssessment,
        searchParameters: {
          'probability': ['0.75'],
        },
      );

      expect(ids(results), equals(['risk-1']));
    });

    test('gt modifier finds resources above threshold', () async {
      await seedRisks();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.RiskAssessment,
        searchParameters: {
          'probability': ['0.5:gt'],
        },
      );

      expect(ids(results), equals(['risk-1']));
    });

    test('no match returns empty', () async {
      await seedRisks();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.RiskAssessment,
        searchParameters: {
          'probability': ['0.99'],
        },
      );

      expect(results, isEmpty);
    });
  });

  // ── Composite search ────────────────────────────────────────────────

  group('Composite search', () {
    fhir.Observation buildCompObs1() => fhir.Observation.fromJson({
          'resourceType': 'Observation',
          'id': 'obs-comp-1',
          'status': 'final',
          'code': {
            'coding': [
              {'system': 'http://loinc.org', 'code': '12345-6'}
            ]
          },
          'subject': {'reference': 'Patient/pt-1'},
        });

    fhir.Observation buildCompObs2() => fhir.Observation.fromJson({
          'resourceType': 'Observation',
          'id': 'obs-comp-2',
          'status': 'amended',
          'code': {
            'coding': [
              {'system': 'http://loinc.org', 'code': '78901-2'}
            ]
          },
          'subject': {'reference': 'Patient/pt-2'},
        });

    Future<void> seedCompObs() async {
      await db.saveResource(buildCompObs1());
      await db.saveResource(buildCompObs2());
    }

    test('composite matches when both components match same resource',
        () async {
      await seedCompObs();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Observation,
        searchParameters: {
          'code-status': ['12345-6\$final'],
        },
      );

      // The hyphen in param name triggers composite; $ separates values
      // code=12345-6 matches obs-comp-1, status=final matches obs-comp-1
      // Intersection = obs-comp-1
      expect(ids(results), equals(['obs-comp-1']));
    });

    test('composite returns empty when components match different resources',
        () async {
      await seedCompObs();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Observation,
        searchParameters: {
          'code-status': ['12345-6\$amended'],
        },
      );

      // code=12345-6 matches obs-comp-1, status=amended matches obs-comp-2
      // Intersection = empty
      expect(results, isEmpty);
    });

    test('composite OR across values finds multiple', () async {
      await seedCompObs();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Observation,
        searchParameters: {
          'code-status': ['12345-6\$final', '78901-2\$amended'],
        },
      );

      expect(ids(results), containsAll(['obs-comp-1', 'obs-comp-2']));
      expect(results.length, 2);
    });
  });

  // ── Reference chaining ──────────────────────────────────────────────

  group('Reference chaining', () {
    Future<void> seedForChaining() async {
      // Save Organization
      await db.saveResource(fhir.Organization.fromJson({
        'resourceType': 'Organization',
        'id': 'org-1',
        'name': 'Mass General',
      }));

      // Save Patient referencing Organization
      await db.saveResource(fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'pt-chain-1',
        'name': [
          {'family': 'ChainSmith', 'given': ['Alice']}
        ],
        'managingOrganization': {'reference': 'Organization/org-1'},
      }));

      // Save Observation referencing Patient
      await db.saveResource(fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': 'obs-chain-1',
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '12345-6'}
          ]
        },
        'subject': {'reference': 'Patient/pt-chain-1'},
      }));
    }

    test('chained reference subject.name finds Observation via Patient name',
        () async {
      await seedForChaining();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Observation,
        searchParameters: {
          'subject.name': ['ChainSmith'],
        },
      );

      expect(ids(results), equals(['obs-chain-1']));
    });

    test('chained reference with non-matching name returns empty', () async {
      await seedForChaining();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Observation,
        searchParameters: {
          'subject.name': ['NonExistent'],
        },
      );

      expect(results, isEmpty);
    });

    test(
        'chained reference managingOrganization.name finds Patient via Org name',
        () async {
      await seedForChaining();

      // The stored search path uses the JSON field name 'managingOrganization',
      // not the FHIR search parameter alias 'organization'.
      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'managingOrganization.name': ['Mass General'],
        },
      );

      expect(ids(results), equals(['pt-chain-1']));
    });
  });
}
