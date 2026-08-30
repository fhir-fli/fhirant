import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/resource_handler.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// AND/OR through the REST path, which is the only place the bug was visible.
///
/// R4 3.1.1.4.17 gives the two separators different meanings:
///
/// > If a parameter repeats, such as `/Patient?language=FR&language=NL`, then
/// > this matches a patient who speaks **both** languages...
/// >
/// > If, instead, the search is to find patients that speak **either**
/// > language, then this is a single parameter with multiple values, separated
/// > by a `,`.
///
/// Two things had to be wrong together for this to fail, and a DAO-level test
/// sees neither: `Uri.queryParameters` keeps only the LAST value of a repeated
/// key, and the parser used to split commas itself, which turned an OR into
/// another AND. So the assertions are made against the handler.
void main() {
  late FhirAntDb db;

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    for (final entry in {
      'both': ['Anna', 'Beth'],
      'onlyA': ['Anna'],
      'onlyB': ['Beth'],
    }.entries) {
      await db.saveResource(
        fhir.Patient.fromJson({
          'resourceType': 'Patient',
          'id': entry.key,
          'name': [
            {'given': entry.value},
          ],
        }),
      );
    }
  });

  tearDown(() async => db.close());

  Future<List<String>> search(String query) async {
    final response = await getResourcesHandler(
      Request('GET', Uri.parse('http://localhost/Patient?$query')),
      'Patient',
      db,
    );
    expect(response.statusCode, equals(200), reason: query);
    final body =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    return (body['entry'] as List<dynamic>? ?? <dynamic>[])
        .map(
          (e) => ((e as Map<String, dynamic>)['resource']
              as Map<String, dynamic>)['id'] as String,
        )
        .toList()
      ..sort();
  }

  test('a known positive, so an empty result below means the join', () async {
    expect(await search('given=Anna'), equals(['both', 'onlyA']));
  });

  test('a repeated parameter is AND: only the record with both', () async {
    expect(await search('given=Anna&given=Beth'), equals(['both']));
  });

  test('a comma is OR: every record with either', () async {
    expect(
      await search('given=Anna,Beth'),
      equals(['both', 'onlyA', 'onlyB']),
    );
  });

  test('the two are not the same query', () async {
    expect(
      await search('given=Anna&given=Beth'),
      isNot(equals(await search('given=Anna,Beth'))),
    );
  });

  test('an OR group ANDed with another parameter', () async {
    await db.saveResource(
      fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'withFamily',
        'name': [
          {
            'given': ['Anna'],
            'family': 'Okello',
          },
        ],
      }),
    );
    expect(
      await search('given=Anna,Beth&family=Okello'),
      equals(['withFamily']),
    );
  });

  test('an escaped comma is one value, not two', () async {
    await db.saveResource(
      fhir.Organization.fromJson({
        'resourceType': 'Organization',
        'id': 'comma',
        'name': 'Clinic, North Wing',
      }),
    );
    await db.saveResource(
      fhir.Organization.fromJson({
        'resourceType': 'Organization',
        'id': 'plain',
        'name': 'Clinic',
      }),
    );
    final response = await getResourcesHandler(
      Request(
        'GET',
        Uri.parse(
          'http://localhost/Organization'
          '?name=${Uri.encodeQueryComponent(r'Clinic\, North')}',
        ),
      ),
      'Organization',
      db,
    );
    final body =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final ids = (body['entry'] as List<dynamic>? ?? <dynamic>[])
        .map(
          (e) => ((e as Map<String, dynamic>)['resource']
              as Map<String, dynamic>)['id'] as String,
        )
        .toList();
    expect(ids, equals(['comma']));
  });
}
