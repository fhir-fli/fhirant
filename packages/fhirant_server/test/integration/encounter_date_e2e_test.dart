import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// `Encounter?date=` through the REST path. Encounter's `date` parameter is
/// Encounter.period; fhir_r4_db before 0.13 wrote no index row for a Period
/// (search_date_range_test pins the prefix semantics against R4B 3.1.1.4.7's
/// own examples), so on the MIMIC load `Encounter?date=…` returned nothing
/// for 637 Encounters. This pins the server path end to end.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    token = generateTestToken(scopes: ['user/*.cruds']);
    for (final (id, start, end) in [
      ('e-jan', '2024-01-10T08:00:00Z', '2024-01-12T17:00:00Z'),
      ('e-mar', '2024-03-01T08:00:00Z', '2024-03-01T09:30:00Z'),
      ('e-open', '2024-06-01T08:00:00Z', null),
    ]) {
      await db.saveResource(
        fhir.Encounter.fromJson({
          'resourceType': 'Encounter',
          'id': id,
          'status': 'finished',
          'class': {
            'system': 'http://terminology.hl7.org/CodeSystem/v3-ActCode',
            'code': 'AMB',
          },
          'period': {'start': start, if (end != null) 'end': end},
        }),
      );
    }
  });
  tearDown(() async => db.close());

  Future<List<String>> ids(String query) async {
    final response = await handler(
      testRequest('GET', '/Encounter?$query', authToken: token),
    );
    expect(response.statusCode, 200, reason: query);
    final body =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    return ((body['entry'] as List?) ?? [])
        .map((e) => e['resource']['id'] as String)
        .toList()
      ..sort();
  }

  test('a Period-valued date parameter is searchable', () async {
    expect(await ids('date=ge2024-01-01'), ['e-jan', 'e-mar', 'e-open']);
    expect(await ids('date=ge2024-02-01'), ['e-mar', 'e-open']);
    expect(await ids('date=le2024-01-31'), ['e-jan']);
  });

  test('eq on a day matches a period lying within it', () async {
    // 3.1.1.4.7 (read whole 2026-09-06): "the date 2013-01-10 specifies all
    // the time from 00:00 on 10-Jan 2013 to immediately before 00:00 on
    // 11-Jan 2013"; eq is "the range of the search value fully contains the
    // range of the target value" (3.1.1.4.5). e-mar lies within its day;
    // e-jan spans three days and does not.
    expect(await ids('date=2024-03-01'), ['e-mar']);
    expect(await ids('date=2024-01-10'), isEmpty);
    expect(await ids('date=2024-01'), ['e-jan']);
  });

  test('sa and eb against a period', () async {
    // sa: the target starts after the search range ends; eb: the target ends
    // before the search range starts (3.1.1.4.5).
    expect(await ids('date=sa2024-02-15'), ['e-mar', 'e-open']);
    expect(await ids('date=eb2024-02-15'), ['e-jan']);
    // An open-ended period never ends before anything.
    expect(await ids('date=eb2025-01-01'), ['e-jan', 'e-mar']);
  });

  test('the value is checked before it is searched', () async {
    final response = await handler(
      testRequest('GET', '/Encounter?date=yesterday', authToken: token),
    );
    expect(response.statusCode, 400);
  });
}
