import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// R4B search.html 3.1.1.6 (hl7.org/fhir/R4B/search.html, read whole
/// 2026-10-17, verbatim): "the server SHALL return the parameters that
/// were actually used to process the search ... In the case of a RESTful
/// search, these parameters are encoded in the self link".
///
/// REVIEW-2026-10-17 finding 2: when EVERY parameter was ignored, the self
/// link echoed the request. `Observation?patiet=Patient/p1` (a typo)
/// returned every Observation under a self link that said the subject
/// filter had run. Dart's `Uri.replace(queryParameters: null)` keeps the
/// original query; that was the whole cause. With one known parameter
/// present the unknown one was already dropped, which the last test pins.
void main() {
  Future<({FhirAntDb db, Handler handler, String token})> setUp() async {
    final server = await createTestServer();
    final token = await issueTestToken(server.db, scopes: ['user/*.rs']);
    for (final (id, patient) in [('o1', 'p1'), ('o2', 'p2')]) {
      await server.db.saveResource(
        fhir.Observation(
          id: id.toFhirString,
          status: fhir.ObservationStatus.final_,
          code: fhir.CodeableConcept(text: 'x'.toFhirString),
          subject: fhir.Reference(reference: 'Patient/$patient'.toFhirString),
        ),
      );
    }
    return (db: server.db, handler: server.handler, token: token);
  }

  Future<(int, Uri)> search(String query) async {
    final s = await setUp();
    final response = await s.handler(
      testRequest('GET', '/Observation?$query', authToken: s.token),
    );
    final body =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final self = (body['link'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((l) => l['relation'] == 'self')['url'] as String;
    await s.db.close();
    return (body['total'] as int, Uri.parse(self));
  }

  test(
      'a search whose only parameter was ignored has no query in its self '
      'link', () async {
    final (total, self) = await search('patiet=Patient/p1');
    expect(total, 2, reason: 'the misspelt filter was not applied');
    expect(self.queryParameters, isEmpty);
    expect(self.toString(), isNot(contains('patiet')));
    expect(self.toString(), isNot(endsWith('?')));
    expect(self.path, '/Observation');
  });

  test('an unknown _sort alone leaves no _sort in the self link', () async {
    final (_, self) = await search('_sort=not-a-param');
    expect(self.queryParameters, isEmpty);
  });

  test('with a used parameter beside it, only the used one is listed',
      () async {
    final (total, self) = await search('subject=Patient/p1&patiet=x');
    expect(total, 1);
    expect(self.queryParameters.keys, ['subject']);
  });
}
