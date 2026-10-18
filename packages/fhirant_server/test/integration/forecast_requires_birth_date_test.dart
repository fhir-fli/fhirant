import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-10-17 finding 7. A forecast for a Patient with no birthDate
/// answered 200 with 16 recommendations: the engine (cicada) assumed
/// 1900-01-01. CDSi Logic Specification v4.6 gives Date of Birth no assumed
/// value (Tables 5-2, 6-14, 7-2: "-") and computes every age date from it
/// (Table 3-6, CALCDTAGE-1..5). The server now refuses such a request, 422,
/// before the engine runs, on both request forms; cicada refuses it too.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    token = await issueTestToken(db, scopes: ['user/*.*']);
    await db.saveResource(fhir.Patient(id: 'nobd'.toFhirString));
    await db.saveResource(
      fhir.Patient(
        id: 'bd'.toFhirString,
        birthDate: fhir.FhirDate.fromString('2025-01-01'),
      ),
    );
  });

  tearDown(() => db.close());

  Future<Response> forecast(String op, Map<String, dynamic> body) async =>
      handler(
        testRequest(
          'POST',
          '/$op',
          body: jsonEncode(body),
          headers: {'content-type': 'application/fhir+json'},
          authToken: token,
        ),
      );

  for (final op in [r'$immds-forecast', r'$immds-forecast-who']) {
    test('$op: a Patient resource with no birthDate is 422', () async {
      final r = await forecast(op, {
        'resourceType': 'Parameters',
        'parameter': [
          {'name': 'assessmentDate', 'valueDate': '2026-10-18'},
          {
            'name': 'patient',
            'resource': {'resourceType': 'Patient', 'id': 'x'},
          },
        ],
      });
      expect(r.statusCode, 422, reason: await r.readAsString());
    });

    test('$op: a stored Patient with no birthDate is 422', () async {
      final r = await forecast(op, {
        'patientId': 'nobd',
        'assessmentDate': '2026-10-18',
      });
      expect(r.statusCode, 422, reason: await r.readAsString());
    });

    test('$op: control, a stored Patient with a birthDate', () async {
      final r = await forecast(op, {
        'patientId': 'bd',
        'assessmentDate': '2026-10-18',
      });
      expect(r.statusCode, 200, reason: await r.readAsString());
    });
  }
}
