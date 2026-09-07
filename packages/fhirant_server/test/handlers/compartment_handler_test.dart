import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/compartment_handler.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// `$everything` and the compartment search, against a real database.
///
/// These used to run against a mock that answered the compartment lookup
/// with whatever ids the test typed, so they asserted the handler's own
/// shape (an `_id` list) and could not see whether a resource was in the
/// compartment. Now the store decides that from the reference index and the
/// published CompartmentDefinition (R4B search.html 3.1.1.2, compartment
/// context; compartmentdefinition-patient).
void main() {
  late FhirAntDb db;

  Map<String, dynamic> observation(String id, String code, String subject) => {
        'resourceType': 'Observation',
        'id': id,
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://loinc.org', 'code': code},
          ],
        },
        'subject': {'reference': subject},
      };

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    await db.saveResource(
      fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'pat-1',
        'name': [
          {'family': 'Smith'},
        ],
      }),
    );
    await db.saveResource(
      fhir.Patient.fromJson({'resourceType': 'Patient', 'id': 'pat-2'}),
    );
    // A patient nothing points at.
    await db.saveResource(
      fhir.Patient.fromJson({'resourceType': 'Patient', 'id': 'pat-3'}),
    );
    await db.saveResource(
      fhir.Observation.fromJson(observation('obs-1', '85354-9', 'Patient/pat-1')),
    );
    await db.saveResource(
      fhir.Observation.fromJson(observation('obs-2', '8480-6', 'Patient/pat-1')),
    );
    await db.saveResource(
      fhir.Observation.fromJson(observation('obs-other', '99999', 'Patient/pat-2')),
    );
    await db.saveResource(
      fhir.Encounter.fromJson({
        'resourceType': 'Encounter',
        'id': 'enc-1',
        'status': 'finished',
        'class': {
          'system': 'http://terminology.hl7.org/CodeSystem/v3-ActCode',
          'code': 'AMB',
        },
      }),
    );
  });
  tearDown(() async => db.close());

  Future<Map<String, dynamic>> body(Response response) async =>
      jsonDecode(await response.readAsString()) as Map<String, dynamic>;

  List<String> ids(Map<String, dynamic> bundle) =>
      ((bundle['entry'] as List?) ?? [])
          .map((e) => (e as Map)['resource']['id'] as String)
          .toList()
        ..sort();

  String? link(Map<String, dynamic> bundle, String relation) {
    for (final l in (bundle['link'] as List?) ?? []) {
      if ((l as Map)['relation'] == relation) return l['url'] as String;
    }
    return null;
  }

  group('everythingHandler', () {
    Future<Response> everything(String type, String id, [String query = '']) =>
        everythingHandler(
          Request(
            'GET',
            Uri.parse('http://localhost:8080/$type/$id/\$everything$query'),
          ),
          type,
          id,
          db,
        );

    test('returns 400 for unsupported compartment type', () async {
      final response = await everything('Organization', 'org-1');
      expect(response.statusCode, equals(400));
      expect((await body(response))['resourceType'], 'OperationOutcome');
    });

    test('returns 404 when focal resource does not exist', () async {
      expect((await everything('Patient', 'missing')).statusCode, 404);
    });

    test('returns Bundle with just focal resource when no linked resources',
        () async {
      final b = await body(await everything('Patient', 'pat-3'));
      expect(b['type'], 'searchset');
      expect(b['total'], 1);
      expect(ids(b), ['pat-3']);
      // And pat-2, whom one Observation names, gets that one and nothing of
      // pat-1's.
      final other = await body(await everything('Patient', 'pat-2'));
      expect(ids(other), ['obs-other', 'pat-2']);
    });

    test('returns Bundle with focal + linked resources', () async {
      final b = await body(await everything('Patient', 'pat-1'));
      expect(b['total'], 3);
      expect(ids(b), ['obs-1', 'obs-2', 'pat-1']);
      expect(
        (b['entry'] as List).first['resource']['resourceType'],
        'Patient',
        reason: 'the focal resource leads',
      );
    });

    test('_type filter limits the linked types; the focal stays', () async {
      final b = await body(
        await everything('Patient', 'pat-1', '?_type=Observation'),
      );
      expect(ids(b), ['obs-1', 'obs-2', 'pat-1']);
      final none = await body(
        await everything('Patient', 'pat-1', '?_type=Condition'),
      );
      expect(ids(none), ['pat-1']);
    });

    test('_since excludes what was updated before it', () async {
      final b = await body(
        await everything('Patient', 'pat-1', '?_since=2200-01-01'),
      );
      expect(ids(b), ['pat-1'], reason: 'nothing was updated after 2200');
      final all = await body(
        await everything('Patient', 'pat-1', '?_since=2000-01-01'),
      );
      expect(all['total'], 3);
    });

    test('_count pagination limits results', () async {
      final b = await body(await everything('Patient', 'pat-1', '?_count=1'));
      expect(b['total'], 3);
      expect(b['entry'], hasLength(1));
      final second = await body(
        await everything('Patient', 'pat-1', '?_count=2&_offset=2'),
      );
      expect(second['entry'], hasLength(1));
    });

    test(r'Encounter $everything works', () async {
      final b = await body(await everything('Encounter', 'enc-1'));
      expect(b['total'], 1);
      expect(ids(b), ['enc-1']);
    });
  });

  group('compartmentSearchHandler', () {
    Future<Response> search(
      String compartment,
      String id,
      String type, [
      String query = '',
    ]) =>
        compartmentSearchHandler(
          Request(
            'GET',
            Uri.parse('http://localhost:8080/$compartment/$id/$type$query'),
          ),
          compartment,
          id,
          type,
          db,
        );

    test('returns 404 for unsupported compartment type', () async {
      expect(
        (await search('Organization', 'org-1', 'Observation')).statusCode,
        404,
      );
    });

    test('returns 400 for invalid resource type', () async {
      expect((await search('Patient', 'pat-1', 'NotAType')).statusCode, 400);
    });

    test('returns 400 for resource type not in compartment', () async {
      final response = await search('Patient', 'pat-1', 'ValueSet');
      expect(response.statusCode, 400);
      expect(
        (await body(response))['issue'][0]['diagnostics'],
        contains('not part of the Patient compartment'),
      );
    });

    test('returns 404 when focal resource does not exist', () async {
      expect(
        (await search('Patient', 'missing', 'Observation')).statusCode,
        404,
      );
    });

    test('returns the resources in the compartment, and only those',
        () async {
      final b = await body(await search('Patient', 'pat-1', 'Observation'));
      expect(b['type'], 'searchset');
      expect(ids(b), ['obs-1', 'obs-2']);
      expect(b['total'], 2);
      expect(
        (b['entry'] as List).first['search']['mode'],
        'match',
      );
    });

    test('ANDs the compartment with the query, and the total follows',
        () async {
      final b = await body(
        await search('Patient', 'pat-1', 'Observation', '?code=85354-9'),
      );
      expect(ids(b), ['obs-1']);
      expect(
        b['total'],
        1,
        reason: "the total is the query's, not the compartment's "
            '(this used to report 2)',
      );
      // A code that exists, on another patient, finds nothing here.
      final none = await body(
        await search('Patient', 'pat-1', 'Observation', '?code=99999'),
      );
      expect(none['entry'], isNull);
      expect(none['total'], 0);
    });

    test('the focal type returns the focal resource', () async {
      final b = await body(await search('Patient', 'pat-1', 'Patient'));
      expect(ids(b), ['pat-1']);
    });

    test('returns empty Bundle when no compartment resources found', () async {
      final b = await body(await search('Patient', 'pat-1', 'Condition'));
      expect(b['entry'], isNull);
      expect(b['total'], 0);
      expect(link(b, 'self'), isNotNull);
    });

    test('pages with links built from the parameters used', () async {
      final b = await body(
        await search('Patient', 'pat-1', 'Observation', '?_count=1&nope=x'),
      );
      expect(b['entry'], hasLength(1));
      expect(b['total'], 2);
      expect(link(b, 'next'), contains('_offset=1'));
      expect(link(b, 'next'), isNot(contains('nope')));
      expect(link(b, 'self'), isNot(contains('nope')));
      expect(link(b, 'last'), contains('_offset=1'));
    });

    test('_total=none pages without a count', () async {
      final b = await body(
        await search(
          'Patient',
          'pat-1',
          'Observation',
          '?_count=1&_total=none',
        ),
      );
      expect(b['total'], isNull);
      expect(link(b, 'next'), isNotNull);
    });

    test('sorts inside the compartment', () async {
      final b = await body(
        await search('Patient', 'pat-1', 'Observation', '?_sort=-_id'),
      );
      expect(
        (b['entry'] as List).map((e) => e['resource']['id']).toList(),
        ['obs-2', 'obs-1'],
      );
    });

    test('Encounter compartment: an Observation by its encounter', () async {
      await db.saveResource(
        fhir.Observation.fromJson({
          ...observation('obs-enc', '12345', 'Patient/pat-2'),
          'encounter': {'reference': 'Encounter/enc-1'},
        }),
      );
      final b = await body(await search('Encounter', 'enc-1', 'Observation'));
      expect(ids(b), ['obs-enc']);
    });
  });
}
