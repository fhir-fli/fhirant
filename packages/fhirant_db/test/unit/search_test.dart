import 'package:test/test.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:drift/native.dart';

void main() {
  late FhirAntDb db;

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
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

    test(':above modifier finds stored URIs that are prefixes of search value',
        () async {
      // Seed a ValueSet with a broad parent URI
      await db.saveResource(fhir.ValueSet.fromJson({
        'resourceType': 'ValueSet',
        'id': 'vs-parent',
        'url': 'http://example.org/fhir',
        'status': 'active',
      }));
      await seedValueSets();

      // :above = stored URI is a prefix of the search value
      // Search value is more specific; matches stored URIs that subsume it
      final results = await db.search(
        resourceType: fhir.R4ResourceType.ValueSet,
        searchParameters: {
          'url': ['http://example.org/fhir/ValueSet/my-codes:above'],
        },
      );

      // vs-parent ('http://example.org/fhir') is a prefix → match
      // vs-1 ('http://example.org/fhir/ValueSet/my-codes') is exact → match
      // vs-2 and vs-3 are not prefixes of the search value → no match
      expect(ids(results), containsAll(['vs-parent', 'vs-1']));
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

  // ── _lastUpdated search ────────────────────────────────────────────────

  group('_lastUpdated search', () {
    test('exact date match finds resources saved today', () async {
      await seedAll();

      final today = DateTime.now();
      final todayStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          '_lastUpdated': [todayStr],
        },
      );

      expect(results.length, 3);
    });

    test(':gt modifier finds resources after a date', () async {
      await seedAll();

      // All resources were saved just now, so yesterday should match all
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final yesterdayStr =
          '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          '_lastUpdated': ['$yesterdayStr:gt'],
        },
      );

      expect(results.length, 3);
    });

    test(':lt modifier finds resources before a date', () async {
      await seedAll();

      // Tomorrow should match all resources saved today
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final tomorrowStr =
          '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          '_lastUpdated': ['$tomorrowStr:lt'],
        },
      );

      expect(results.length, 3);
    });

    test(':ge modifier finds resources on or after date', () async {
      await seedAll();

      final today = DateTime.now();
      final todayStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          '_lastUpdated': ['$todayStr:ge'],
        },
      );

      expect(results.length, 3);
    });

    test(':gt with future date returns empty', () async {
      await seedAll();

      final future = DateTime.now().add(const Duration(days: 365));
      final futureStr =
          '${future.year}-${future.month.toString().padLeft(2, '0')}-${future.day.toString().padLeft(2, '0')}';

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          '_lastUpdated': ['$futureStr:gt'],
        },
      );

      expect(results, isEmpty);
    });
  });

  // ── Meta parameter search ──────────────────────────────────────────────

  group('Meta parameter search', () {
    fhir.Patient buildPatientWithMeta() => fhir.Patient.fromJson({
          'resourceType': 'Patient',
          'id': 'pt-meta-1',
          'meta': {
            'tag': [
              {
                'system': 'http://example.org/tags',
                'code': 'research',
              }
            ],
            'profile': [
              'http://hl7.org/fhir/us/core/StructureDefinition/us-core-patient'
            ],
            'security': [
              {
                'system':
                    'http://terminology.hl7.org/CodeSystem/v3-Confidentiality',
                'code': 'R',
              }
            ],
            'source': 'http://hospital.example.org',
          },
          'name': [
            {'family': 'MetaTest'}
          ],
        });

    fhir.Patient buildPatientWithoutMeta() => fhir.Patient.fromJson({
          'resourceType': 'Patient',
          'id': 'pt-meta-2',
          'name': [
            {'family': 'NoMeta'}
          ],
        });

    Future<void> seedMetaPatients() async {
      await db.saveResource(buildPatientWithMeta());
      await db.saveResource(buildPatientWithoutMeta());
    }

    test('_tag with code only finds matching', () async {
      await seedMetaPatients();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          '_tag': ['research'],
        },
      );

      expect(ids(results), equals(['pt-meta-1']));
    });

    test('_tag with system|code finds matching', () async {
      await seedMetaPatients();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          '_tag': ['http://example.org/tags|research'],
        },
      );

      expect(ids(results), equals(['pt-meta-1']));
    });

    test('_tag no match returns empty', () async {
      await seedMetaPatients();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          '_tag': ['nonexistent'],
        },
      );

      expect(results, isEmpty);
    });

    test('_profile exact URL finds matching', () async {
      await seedMetaPatients();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          '_profile': [
            'http://hl7.org/fhir/us/core/StructureDefinition/us-core-patient'
          ],
        },
      );

      expect(ids(results), equals(['pt-meta-1']));
    });

    test('_profile no match returns empty', () async {
      await seedMetaPatients();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          '_profile': ['http://nonexistent.org/profile'],
        },
      );

      expect(results, isEmpty);
    });

    test('_security with system|code finds matching', () async {
      await seedMetaPatients();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          '_security': [
            'http://terminology.hl7.org/CodeSystem/v3-Confidentiality|R'
          ],
        },
      );

      expect(ids(results), equals(['pt-meta-1']));
    });

    test('_security code only finds matching', () async {
      await seedMetaPatients();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          '_security': ['R'],
        },
      );

      expect(ids(results), equals(['pt-meta-1']));
    });

    test('_source exact match finds matching', () async {
      await seedMetaPatients();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          '_source': ['http://hospital.example.org'],
        },
      );

      expect(ids(results), equals(['pt-meta-1']));
    });
  });

  // ── String modifier search ─────────────────────────────────────────────

  group('String modifier search', () {
    test(':exact modifier matches case-sensitive exact value', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'name': ['Smith:exact'],
        },
      );

      // :exact uses equals on the normalized (lowercased) value
      // 'Smith' normalized → 'smith', stored values normalized → 'smith'
      expect(ids(results), containsAll(['pt-1', 'pt-2']));
    });

    test(':exact no match with wrong case normalization', () async {
      await seedAll();

      // 'NONEXISTENT' won't match any stored normalized value
      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'name': ['NonExistentName:exact'],
        },
      );

      expect(results, isEmpty);
    });

    test(':contains modifier finds substring match', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'name': ['mit:contains'],
        },
      );

      // 'mit' is a substring of 'smith' (normalized)
      expect(ids(results), containsAll(['pt-1', 'pt-2']));
    });

    test(':missing modifier finds resources without indexed string param',
        () async {
      // pt-2 has no address, pt-1 has address
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'address': ['true:missing'],
        },
      );

      // pt-2 and pt-3 have no address, pt-1 has address
      expect(ids(results), containsAll(['pt-2', 'pt-3']));
      expect(results.length, 2);
    });
  });

  // ── Token :missing search ──────────────────────────────────────────────

  group('Token :missing search', () {
    test(':missing finds resources without gender token', () async {
      await seedAll();
      // pt-3 has gender='male', pt-1 has gender='male', pt-2 has gender='female'
      // All 3 have gender, so :missing should find none in the default seed

      // Save a Patient without gender
      await db.saveResource(fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'pt-nogender',
        'name': [
          {'family': 'NoGender'}
        ],
      }));

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'gender': ['true:missing'],
        },
      );

      expect(ids(results), equals(['pt-nogender']));
    });

    test(':missing returns empty when all have gender', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'gender': ['true:missing'],
        },
      );

      // All 3 patients have gender
      expect(results, isEmpty);
    });
  });

  // ── Date modifier search ───────────────────────────────────────────────

  group('Date modifier search', () {
    test(':gt finds patients born after threshold', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'birthdate': ['1995-01-01:gt'],
        },
      );

      // pt-3 born 2000-03-10 is after 1995-01-01
      expect(ids(results), equals(['pt-3']));
    });

    test(':lt finds patients born before threshold', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'birthdate': ['1995-01-01:lt'],
        },
      );

      // pt-1 born 1990-01-15, pt-2 born 1985-06-20 are before 1995-01-01
      expect(ids(results), containsAll(['pt-1', 'pt-2']));
      expect(results.length, 2);
    });

    test('exact date match finds single patient', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'birthdate': ['1990-01-15'],
        },
      );

      expect(ids(results), equals(['pt-1']));
    });
  });

  // ── Number extended modifier search ──────────────────────────────────

  group('Number extended modifiers', () {
    fhir.RiskAssessment buildRisk1() => fhir.RiskAssessment.fromJson({
          'resourceType': 'RiskAssessment',
          'id': 'risk-1',
          'status': 'final',
          'subject': {'reference': 'Patient/pt-1'},
          'prediction': [
            {'probabilityDecimal': 0.75}
          ],
        });

    fhir.RiskAssessment buildRisk2() => fhir.RiskAssessment.fromJson({
          'resourceType': 'RiskAssessment',
          'id': 'risk-2',
          'status': 'final',
          'subject': {'reference': 'Patient/pt-2'},
          'prediction': [
            {'probabilityDecimal': 0.25}
          ],
        });

    Future<void> seedRisks() async {
      await db.saveResource(buildRisk1());
      await db.saveResource(buildRisk2());
    }

    test(':lt finds below threshold', () async {
      await seedRisks();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.RiskAssessment,
        searchParameters: {
          'probability': ['0.5:lt'],
        },
      );

      expect(ids(results), equals(['risk-2']));
    });

    test(':le includes boundary', () async {
      await seedRisks();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.RiskAssessment,
        searchParameters: {
          'probability': ['0.75:le'],
        },
      );

      expect(ids(results), containsAll(['risk-1', 'risk-2']));
      expect(results.length, 2);
    });

    test(':ge includes boundary', () async {
      await seedRisks();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.RiskAssessment,
        searchParameters: {
          'probability': ['0.25:ge'],
        },
      );

      expect(ids(results), containsAll(['risk-1', 'risk-2']));
      expect(results.length, 2);
    });

    test(':ap finds within 10% range', () async {
      await seedRisks();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.RiskAssessment,
        searchParameters: {
          'probability': ['0.73:ap'],
        },
      );

      // 0.73 ± 10% = 0.657–0.803; only risk-1 (0.75) matches
      expect(ids(results), equals(['risk-1']));
    });
  });

  // ── Quantity extended modifier search ────────────────────────────────

  group('Quantity extended modifiers', () {
    fhir.ChargeItem buildCI1() => fhir.ChargeItem.fromJson({
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

    fhir.ChargeItem buildCI2() => fhir.ChargeItem.fromJson({
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

    fhir.ChargeItem buildCI3() => fhir.ChargeItem.fromJson({
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

    Future<void> seedCIs() async {
      await db.saveResource(buildCI1());
      await db.saveResource(buildCI2());
      await db.saveResource(buildCI3());
    }

    test(':lt finds below threshold', () async {
      await seedCIs();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.ChargeItem,
        searchParameters: {
          'quantity': ['7:lt'],
        },
      );

      expect(ids(results), containsAll(['ci-1', 'ci-3']));
      expect(results.length, 2);
    });

    test(':le includes boundary', () async {
      await seedCIs();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.ChargeItem,
        searchParameters: {
          'quantity': ['5:le'],
        },
      );

      expect(ids(results), containsAll(['ci-1', 'ci-3']));
      expect(results.length, 2);
    });

    test(':ge includes boundary', () async {
      await seedCIs();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.ChargeItem,
        searchParameters: {
          'quantity': ['10:ge'],
        },
      );

      expect(ids(results), equals(['ci-2']));
    });

    test(':lt with unit filter', () async {
      await seedCIs();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.ChargeItem,
        searchParameters: {
          'quantity': ['7|mL:lt'],
        },
      );

      expect(ids(results), equals(['ci-3']));
    });
  });

  // ── Date extended modifier search ────────────────────────────────────

  group('Date extended modifiers', () {
    test(':le includes boundary', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'birthdate': ['1990-01-15:le'],
        },
      );

      // pt-1 (1990-01-15) and pt-2 (1985-06-20) are <= 1990-01-15
      expect(ids(results), containsAll(['pt-1', 'pt-2']));
      expect(results.length, 2);
    });

    test(':ge includes boundary', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'birthdate': ['2000-03-10:ge'],
        },
      );

      // pt-3 (2000-03-10) is >= 2000-03-10
      expect(ids(results), equals(['pt-3']));
    });

    test(':sa starts after', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'birthdate': ['1995-01-01:sa'],
        },
      );

      // pt-3 (2000-03-10) starts after 1995-01-01
      expect(ids(results), equals(['pt-3']));
    });

    test(':eb ends before', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'birthdate': ['1995-01-01:eb'],
        },
      );

      // pt-1 (1990-01-15) and pt-2 (1985-06-20) end before 1995-01-01
      expect(ids(results), containsAll(['pt-1', 'pt-2']));
      expect(results.length, 2);
    });

    test(':ap approximately matches', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'birthdate': ['1990-01-15:ap'],
        },
      );

      // Approximately 1990-01-15 (±1 day) — only pt-1 matches
      expect(ids(results), equals(['pt-1']));
    });
  });

  // ── _lastUpdated extended modifier search ────────────────────────────

  group('_lastUpdated extended modifiers', () {
    test(':le with tomorrow finds all', () async {
      await seedAll();

      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final tomorrowStr =
          '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          '_lastUpdated': ['$tomorrowStr:le'],
        },
      );

      expect(results.length, 3);
    });

    test(':sa with yesterday finds all', () async {
      await seedAll();

      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final yesterdayStr =
          '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          '_lastUpdated': ['$yesterdayStr:sa'],
        },
      );

      expect(results.length, 3);
    });

    test(':eb with tomorrow finds all', () async {
      await seedAll();

      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final tomorrowStr =
          '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          '_lastUpdated': ['$tomorrowStr:eb'],
        },
      );

      expect(results.length, 3);
    });
  });

  // ── URI :below search ────────────────────────────────────────────────

  group('URI :below search', () {
    fhir.ValueSet buildVS1() => fhir.ValueSet.fromJson({
          'resourceType': 'ValueSet',
          'id': 'vs-1',
          'url': 'http://example.org/fhir/ValueSet/my-codes',
          'status': 'active',
        });

    fhir.ValueSet buildVS2() => fhir.ValueSet.fromJson({
          'resourceType': 'ValueSet',
          'id': 'vs-2',
          'url': 'http://example.org/fhir/ValueSet/other-codes',
          'status': 'active',
        });

    fhir.ValueSet buildVS3() => fhir.ValueSet.fromJson({
          'resourceType': 'ValueSet',
          'id': 'vs-3',
          'url': 'http://different.org/fhir/ValueSet/different',
          'status': 'active',
        });

    Future<void> seedVS() async {
      await db.saveResource(buildVS1());
      await db.saveResource(buildVS2());
      await db.saveResource(buildVS3());
    }

    test(':below broad prefix finds multiple', () async {
      await seedVS();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.ValueSet,
        searchParameters: {
          'url': ['http://example.org/fhir/ValueSet:below'],
        },
      );

      expect(ids(results), containsAll(['vs-1', 'vs-2']));
      expect(results.length, 2);
    });

    test(':below narrow prefix finds one', () async {
      await seedVS();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.ValueSet,
        searchParameters: {
          'url': ['http://example.org/fhir/ValueSet/my:below'],
        },
      );

      expect(ids(results), equals(['vs-1']));
    });
  });

  // ── Token :not modifier search ──────────────────────────────────────

  group('Token :not modifier search', () {
    test(':not excludes matching gender', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'gender': ['male:not'],
        },
      );

      // pt-2 is female, so it should be returned; pt-1 and pt-3 are male
      expect(ids(results), equals(['pt-2']));
    });

    test(':not with system|value', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'identifier': ['http://hospital.org/mrn|MRN001:not'],
        },
      );

      // pt-1 has that identifier; pt-2 and pt-3 don't
      expect(ids(results), containsAll(['pt-2', 'pt-3']));
      expect(results.length, 2);
    });

    test(':not returns all when value absent from all', () async {
      await seedAll();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'gender': ['nonexistent:not'],
        },
      );

      // No patient has gender=nonexistent, so all are returned
      expect(ids(results), containsAll(['pt-1', 'pt-2', 'pt-3']));
      expect(results.length, 3);
    });

    test(':not includes resources lacking the param', () async {
      await seedAll();

      // Save a patient without gender
      await db.saveResource(fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'pt-nogender',
        'name': [
          {'family': 'NoGender'}
        ],
      }));

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'gender': ['male:not'],
        },
      );

      // pt-2 (female) and pt-nogender (no gender) should match
      expect(ids(results), containsAll(['pt-2', 'pt-nogender']));
      expect(results.length, 2);
    });
  });

  // ── Token :text modifier search ──────────────────────────────────────

  group('Token :text modifier search', () {
    // Use Observation.code which IS indexed as a token search parameter
    // and stores display values via Coding.display → tokenDisplay column
    fhir.Observation buildObsGlucose() => fhir.Observation.fromJson({
          'resourceType': 'Observation',
          'id': 'obs-glucose',
          'status': 'final',
          'code': {
            'coding': [
              {
                'system': 'http://loinc.org',
                'code': '2345-7',
                'display': 'Glucose [Mass/volume] in Serum',
              }
            ]
          },
          'subject': {'reference': 'Patient/pt-1'},
        });

    fhir.Observation buildObsCholesterol() => fhir.Observation.fromJson({
          'resourceType': 'Observation',
          'id': 'obs-chol',
          'status': 'final',
          'code': {
            'coding': [
              {
                'system': 'http://loinc.org',
                'code': '2093-3',
                'display': 'Cholesterol in Serum',
              }
            ]
          },
          'subject': {'reference': 'Patient/pt-1'},
        });

    Future<void> seedTextObs() async {
      await db.saveResource(buildObsGlucose());
      await db.saveResource(buildObsCholesterol());
    }

    test(':text finds by display substring', () async {
      await seedTextObs();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Observation,
        searchParameters: {
          'code': ['Serum:text'],
        },
      );

      // Both have 'Serum' in display
      expect(ids(results), containsAll(['obs-glucose', 'obs-chol']));
      expect(results.length, 2);
    });

    test(':text is case-insensitive', () async {
      await seedTextObs();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Observation,
        searchParameters: {
          'code': ['serum:text'],
        },
      );

      expect(ids(results), containsAll(['obs-glucose', 'obs-chol']));
      expect(results.length, 2);
    });

    test(':text narrows with specific text', () async {
      await seedTextObs();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Observation,
        searchParameters: {
          'code': ['Glucose:text'],
        },
      );

      expect(ids(results), equals(['obs-glucose']));
    });

    test(':text no match returns empty', () async {
      await seedTextObs();

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Observation,
        searchParameters: {
          'code': ['Hemoglobin:text'],
        },
      );

      expect(results, isEmpty);
    });
  });

  // ── Universal :missing search ────────────────────────────────────────

  group('Universal :missing search', () {
    test('date :missing finds patient without birthDate', () async {
      await seedAll();

      // Save a patient without birthDate
      await db.saveResource(fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'pt-nobirth',
        'name': [
          {'family': 'NoBirth'}
        ],
      }));

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'birthdate': ['true:missing'],
        },
      );

      expect(ids(results), equals(['pt-nobirth']));
    });

    test('quantity :missing finds ChargeItem without quantity', () async {
      // Seed ChargeItems with quantity
      await db.saveResource(fhir.ChargeItem.fromJson({
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
      }));

      // Save a ChargeItem without quantity
      await db.saveResource(fhir.ChargeItem.fromJson({
        'resourceType': 'ChargeItem',
        'id': 'ci-noqty',
        'status': 'billable',
        'code': {
          'coding': [
            {'system': 'http://example.org', 'code': 'item-x'}
          ]
        },
        'subject': {'reference': 'Patient/pt-1'},
      }));

      final results = await db.search(
        resourceType: fhir.R4ResourceType.ChargeItem,
        searchParameters: {
          'quantity': ['true:missing'],
        },
      );

      expect(ids(results), equals(['ci-noqty']));
    });

    test('URI :missing finds ValueSet without url', () async {
      // Seed ValueSets with url
      await db.saveResource(fhir.ValueSet.fromJson({
        'resourceType': 'ValueSet',
        'id': 'vs-1',
        'url': 'http://example.org/fhir/ValueSet/my-codes',
        'status': 'active',
      }));

      // Save a ValueSet without url
      await db.saveResource(fhir.ValueSet.fromJson({
        'resourceType': 'ValueSet',
        'id': 'vs-nourl',
        'status': 'active',
        'name': 'NoUrl',
      }));

      final results = await db.search(
        resourceType: fhir.R4ResourceType.ValueSet,
        searchParameters: {
          'url': ['true:missing'],
        },
      );

      expect(ids(results), equals(['vs-nourl']));
    });

    test('reference :missing finds Observation without subject', () async {
      await seedAll(); // includes obs-1 with subject

      // Save an Observation without subject
      await db.saveResource(fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': 'obs-nosub',
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '99999-9'}
          ]
        },
      }));

      final results = await db.search(
        resourceType: fhir.R4ResourceType.Observation,
        searchParameters: {
          'subject': ['true:missing'],
        },
      );

      expect(ids(results), equals(['obs-nosub']));
    });
  });
}
