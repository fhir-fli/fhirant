import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/filter_evaluator.dart';
import 'package:fhirant_server/src/utils/filter_expression.dart';
import 'package:test/test.dart';

/// The evaluator answers a `_filter` by running ordinary searches and
/// combining the id sets. What it cannot answer it refuses, because a result
/// set produced by a *different* operator is a wrong answer, not a limitation.
Future<void> main() async {
  late FhirAntDb db;
  late FilterEvaluator evaluator;

  Future<Set<String>> run(String filter) =>
      evaluator.evaluate(parseFilter(filter));

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    evaluator = FilterEvaluator(db, fhir.R4ResourceType.Patient);

    await db.saveResource(
      fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'okello',
        'name': [
          {
            'family': 'Okello',
            'given': ['Anna'],
          },
        ],
        'gender': 'female',
        'birthDate': '1980-05-05',
      }),
    );
    await db.saveResource(
      fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'okot',
        'name': [
          {
            'family': 'Okot',
            'given': ['Beth'],
          },
        ],
        'gender': 'male',
        'birthDate': '1990-01-01',
      }),
    );
    await db.saveResource(
      fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'nameless',
        'gender': 'female',
      }),
    );
  });

  tearDown(() => db.close());

  group('operators this server can answer', () {
    test('co runs as :contains', () async {
      expect(await run('family co "kel"'), {'okello'});
    });

    test('sw runs as the default string match', () async {
      expect(await run('family sw "Oko"'), {'okot'});
    });

    test('eq on a token is the plain value', () async {
      expect(await run('gender eq female'), {'okello', 'nameless'});
    });

    test('pr true is :missing=false, pr false is :missing=true', () async {
      expect(await run('family pr true'), {'okello', 'okot'});
      expect(await run('family pr false'), {'nameless'});
    });

    test('a date comparator becomes a prefix', () async {
      expect(await run('birthdate gt 1985-01-01'), {'okot'});
      expect(await run('birthdate le 1985-01-01'), {'okello'});
    });
  });

  group('logic', () {
    test('and intersects', () async {
      expect(await run('gender eq female and family co "kel"'), {'okello'});
    });

    test('or unions', () async {
      expect(
        await run('family sw "Okello" or family sw "Okot"'),
        {'okello', 'okot'},
      );
    });

    test('not complements over every resource of the type', () async {
      expect(await run('not(gender eq female)'), {'okot'});
    });

    test('left to right, no precedence, as 3.1.3.1 requires', () async {
      // (gender eq male OR gender eq female) AND family co "kel" == {okello}.
      // With boolean precedence it would be gender eq male OR (...) and would
      // also contain okot.
      expect(
        await run('gender eq male or gender eq female and family co "kel"'),
        {'okello'},
      );
    });
  });

  group('refusals, each with a reason', () {
    Future<void> refuses(String filter, Matcher message) async {
      await expectLater(
        run(filter),
        throwsA(
          isA<FilterNotSupported>()
              .having((e) => e.message, 'message', message),
        ),
      );
    }

    test('eq on a string', () async {
      await refuses('family eq "Okello"', contains('case-insensitively'));
    });

    test('ne', () async {
      await refuses('gender ne female', contains('not the complement'));
    });

    test('ew', () async {
      await refuses('family ew "llo"', contains('ends-with'));
    });

    test('po', () async {
      await refuses('birthdate po 1980', contains('period overlap'));
    });

    test('ss and sb', () async {
      await refuses('gender ss female', contains('subsumption'));
      await refuses('gender sb female', contains('subsumption'));
    });

    test('a path carrying a sub-filter', () async {
      await refuses(
        'link[type eq refer].other re Patient/1',
        contains('sub-filter'),
      );
    });

    test('a parameter this resource type does not have', () async {
      await refuses('nonsense eq 1', contains('not a search parameter'));
    });

    test('co on a non-string parameter', () async {
      await refuses('gender co fem', contains('co'));
    });

    test('a comparator the parameter does not declare', () async {
      // gender is a token; the published definition declares no comparators.
      await refuses('gender gt female', contains('not a comparator'));
    });
  });
}
