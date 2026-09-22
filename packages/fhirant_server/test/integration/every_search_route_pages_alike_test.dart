@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// Every route that pages a set of resources pages it the same way.
///
/// R4B search.html, read whole 2026-09-22, verbatim: "the server SHALL
/// return the parameters that were actually used to process the search"
/// and "In the case of a RESTful search, these parameters are encoded in
/// the self link"; and on `_total=none`: "none: there is no need to
/// populate the total count". Before the shared page builder (2026-09-22)
/// the searchset bundle, its links and its total were assembled at nine
/// sites in two files, with the total decided four ways.
///
/// Four routes page: the type search, the system search, the compartment
/// search, and $everything. Each gets three matches, asks for the middle
/// one, and must answer the same link set, drop an unknown parameter from
/// its self link, and honour `_total=none`.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    token = await issueTestToken(
      db,
      username: 'page-admin',
      role: 'admin',
      scopes: ['system/*.*'],
    );
    await db.saveResource(fhir.Patient(id: 'p1'.toFhirString));
    for (final n in ['1', '2', '3']) {
      await db.saveResource(
        fhir.Observation(
          id: 'o$n'.toFhirString,
          status: fhir.ObservationStatus.final_,
          code: fhir.CodeableConcept(text: 'obs $n'.toFhirString),
          subject: fhir.Reference(reference: 'Patient/p1'.toFhirString),
        ),
      );
    }
  });

  tearDown(() => db.close());

  const routes = <String, String>{
    'type search': '/Observation?subject=Patient/p1',
    'system search': '/?_type=Observation',
    'compartment search': '/Patient/p1/Observation?',
    r'$everything': r'/Patient/p1/$everything?_type=Observation',
  };

  Future<Map<String, dynamic>> page(String url) async {
    final response = await handler(testRequest('GET', url, authToken: token));
    final body = await response.readAsString();
    expect(response.statusCode, 200, reason: '$url -> $body');
    return jsonDecode(body) as Map<String, dynamic>;
  }

  test('the middle page of three carries the same links everywhere', () async {
    final unalike = <String>[];
    for (final route in routes.entries) {
      final joiner = route.value.endsWith('?') ? '' : '&';
      // The system search refuses a parameter that is not common to every
      // type named (its own documented rule), so it gets no unknown one.
      final unknown = route.key == 'system search' ? '' : '&zzz=1';
      final bundle =
          await page('${route.value}${joiner}_count=1&_offset=1$unknown');
      final links = (bundle['link'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .map((l) => '${l['relation']}')
          .toSet();
      final self = (bundle['link'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .firstWhere((l) => l['relation'] == 'self', orElse: () => {})['url'];
      // $everything counts the focal Patient among its results.
      final expectedTotal = route.key == r'$everything' ? 4 : 3;
      final expectedLinks = {'self', 'first', 'previous', 'next', 'last'};
      final problems = <String>[
        if (links.length != expectedLinks.length ||
            !links.containsAll(expectedLinks))
          'links $links',
        if ('$self'.contains('zzz')) 'self link echoes an unknown parameter',
        if (bundle['total'] != expectedTotal) 'total ${bundle['total']}',
        if ((bundle['entry'] as List?)?.length != 1)
          'entries ${(bundle['entry'] as List?)?.length}',
      ];
      if (problems.isNotEmpty) {
        unalike.add('${route.key}: ${problems.join('; ')}');
      }
    }
    expect(unalike, isEmpty);
  });

  test('_total=none leaves the total out everywhere', () async {
    final withTotal = <String>[];
    for (final route in routes.entries) {
      final joiner = route.value.endsWith('?') ? '' : '&';
      final bundle = await page('${route.value}${joiner}_count=1&_total=none');
      if (bundle.containsKey('total')) {
        withTotal.add('${route.key}: total ${bundle['total']}');
      }
    }
    expect(withTotal, isEmpty);
  });
}
