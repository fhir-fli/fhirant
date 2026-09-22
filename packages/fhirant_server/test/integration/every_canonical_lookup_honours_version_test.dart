@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// Every operation that finds an artefact by canonical URL accepts the
/// `url|version` form and picks that version.
///
/// R4B references.html, read whole 2026-09-22, verbatim: "References of
/// type canonical may include a version, in order be precise about which
/// version of the resource is being referred to. To do this, append the
/// version to the reference with a '|'"; and "Servers SHOULD support
/// version specific searching for canonical URLs by automatically
/// detecting the presence of a |[version] and performing the appropriate
/// search"; with no version, "the system using the reference should pick
/// the latest version". Before the shared finder (2026-09-22) the search
/// by canonical was written at eight sites, each splitting the version
/// itself or leaving it to the store; this test passed on all of them
/// (measured 2026-09-22) and pins the behaviour the one finder keeps.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;

  const url = 'http://example.org/fhir/ValueSet/vs';
  const system = 'http://example.org/fhir/CodeSystem/cs';

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    token = await issueTestToken(
      db,
      username: 'canon-admin',
      role: 'admin',
      scopes: ['system/*.*'],
    );
    for (final v in ['1', '2']) {
      await db.saveResource(
        fhir.CodeSystem(
          id: 'cs$v'.toFhirString,
          url: system.toFhirUri,
          version: v.toFhirString,
          status: fhir.PublicationStatus.active,
          content: fhir.CodeSystemContentMode.complete,
          concept: [
            fhir.CodeSystemConcept(
              code: 'c$v'.toFhirCode,
              display: 'code of version $v'.toFhirString,
            ),
          ],
        ),
      );
      await db.saveResource(
        fhir.ValueSet(
          id: 'vs$v'.toFhirString,
          url: url.toFhirUri,
          version: v.toFhirString,
          status: fhir.PublicationStatus.active,
          compose: fhir.ValueSetCompose(
            include: [
              fhir.ValueSetInclude(
                system: system.toFhirUri,
                version: v.toFhirString,
                concept: [
                  fhir.ValueSetConcept(code: 'c$v'.toFhirCode),
                ],
              ),
            ],
          ),
        ),
      );
    }
  });

  tearDown(() => db.close());

  Future<Map<String, dynamic>> get(String path) async {
    final response = await handler(testRequest('GET', path, authToken: token));
    final body = await response.readAsString();
    expect(response.statusCode, 200, reason: '$path -> $body');
    return jsonDecode(body) as Map<String, dynamic>;
  }

  test(r'$expand by url|version expands that version', () async {
    final expanded = await get(r'/ValueSet/$expand?url=' '$url|2');
    final codes = ((expanded['expansion'] as Map)['contains'] as List)
        .cast<Map<String, dynamic>>()
        .map((c) => c['code'])
        .toList();
    expect(codes, ['c2']);
  });

  test(r'$expand by url|version that is not held answers 404', () async {
    final response = await handler(
      testRequest('GET', r'/ValueSet/$expand?url=' '$url|3', authToken: token),
    );
    expect(response.statusCode, 404, reason: await response.readAsString());
  });

  test(r'$lookup by system|version looks up in that version', () async {
    final looked =
        await get(r'/CodeSystem/$lookup?system=' '$system|1&code=c1');
    final display = (looked['parameter'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((p) => p['name'] == 'display')['valueString'];
    expect(display, 'code of version 1');
  });
}
