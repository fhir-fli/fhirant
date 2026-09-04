import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:test/test.dart';

import 'test_helpers.dart';

/// Paging must not depend on counting.
///
/// The `next` link was derived from `offset + count < total`, so a client
/// sending `_total=none` — the request that makes a page cheap on a large
/// database — got no `next` link and could not page at all. R4 search.html
/// makes `total` optional and the links the paging mechanism; the server
/// fetches one row past the page and emits `next` when it exists.
void main() {
  Future<Map<String, dynamic>> page(String query) async {
    final server = await createTestServer();
    final token = generateTestToken(scopes: ['user/*.cruds']);
    for (var i = 0; i < 5; i++) {
      await server.db.saveResource(
        fhir.Patient(
          id: 'p$i'.toFhirString,
          gender: fhir.AdministrativeGender.female,
        ),
      );
    }
    final response = await server.handler(
      testRequest('GET', '/Patient?$query', authToken: token),
    );
    expect(response.statusCode, 200);
    final bundle =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    await server.db.close();
    return bundle;
  }

  String? link(Map<String, dynamic> bundle, String relation) {
    for (final l in (bundle['link'] as List?) ?? []) {
      if ((l as Map)['relation'] == relation) return l['url'] as String;
    }
    return null;
  }

  test('_total=none still gets a next link when more rows exist', () async {
    final bundle = await page('gender=female&_count=2&_total=none');
    expect(bundle['total'], isNull);
    expect((bundle['entry'] as List).length, 2);
    expect(link(bundle, 'next'), contains('_offset=2'));
  });

  test('no next link on the last page, with or without a total', () async {
    final counted = await page('gender=female&_count=2&_offset=4');
    expect((counted['entry'] as List).length, 1);
    expect(link(counted, 'next'), isNull);

    final uncounted =
        await page('gender=female&_count=2&_offset=4&_total=none');
    expect((uncounted['entry'] as List).length, 1);
    expect(link(uncounted, 'next'), isNull);
  });

  test('the probe row never leaks into the page', () async {
    final bundle = await page('gender=female&_count=2');
    expect((bundle['entry'] as List).length, 2);
    expect(bundle['total'], 5);
  });
}
