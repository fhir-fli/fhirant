@Timeout(Duration(minutes: 3))
library;

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// Every search route honours `Prefer: handling`.
///
/// R4B search.html, "Unknown and unsupported parameters", read whole
/// 2026-10-01, verbatim: "servers SHOULD ignore unknown or unsupported
/// parameters"; "Prefer: handling=strict: Client requests that the server
/// return an error for any unknown or unsupported parameter"; "Prefer:
/// handling=lenient: Client requests that the server ignore any unknown or
/// unsupported parameter"; "Servers SHOULD honor the client's request".
///
/// An unknown `_sort` rule is an unsupported parameter: dropped and left
/// out of the self link under lenient (the default), refused under strict.
/// Found by the HAPI differential (case `sort-unknown-key`), which sent no
/// Prefer header; the triage item D1 asked whether to refuse it always.
/// The spec's mechanism is the header, so the test pins that mechanism on
/// every route that searches.
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
      username: 'strict-admin',
      role: 'admin',
      scopes: ['system/*.*'],
    );
    await db.saveResource(fhir.Patient(id: 'p1'.toFhirString));
    await db.saveResource(
      fhir.Observation(
        id: 'o1'.toFhirString,
        status: fhir.ObservationStatus.final_,
        code: fhir.CodeableConcept(text: 'obs'.toFhirString),
        subject: fhir.Reference(reference: 'Patient/p1'.toFhirString),
      ),
    );
  });

  tearDown(() => db.close());

  const routes = <String, String>{
    'type search': '/Observation?',
    'system search': '/?_type=Observation&',
    'compartment search': '/Patient/p1/Observation?',
  };

  Future<String> status(String url, {String? prefer}) async {
    final response = await handler(
      testRequest(
        'GET',
        url,
        authToken: token,
        headers: {if (prefer != null) 'prefer': 'handling=$prefer'},
      ),
    );
    final body = await response.readAsString();
    if (response.statusCode == 200) return '200';
    final head = body.length > 160 ? body.substring(0, 160) : body;
    return '${response.statusCode} $head';
  }

  for (final unsupported in ['_sort=not-a-search-parameter', 'zzz=1']) {
    test('strict refuses $unsupported on every search route', () async {
      final lenient = <String>[];
      for (final route in routes.entries) {
        final code =
            await status('${route.value}$unsupported', prefer: 'strict');
        if (!code.startsWith('400')) lenient.add('${route.key} -> $code');
      }
      expect(lenient, isEmpty);
    });

    test('lenient (and no header) drops $unsupported on every search route',
        () async {
      final refused = <String>[];
      for (final route in routes.entries) {
        for (final prefer in [null, 'lenient']) {
          final code =
              await status('${route.value}$unsupported', prefer: prefer);
          if (code != '200') refused.add('${route.key} ($prefer) -> $code');
        }
      }
      expect(refused, isEmpty);
    });
  }
}
