import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// HL7 Immunization Decision Support Forecast IG 1.0.0,
/// OperationDefinition ImmDSForecastOperation (package hl7.fhir.us.immds
/// 1.0.0, read 2026-10-18): input `patient`, min 1, max 1, type Patient.
/// REVIEW-2026-10-17 finding 15: a Parameters body without it reached the
/// engine, which threw, and the handler answered 500 and logged SEVERE: the
/// client's omission reported as the server's failure.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    token = await issueTestToken(db, scopes: ['user/*.*']);
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
    test('$op: Parameters with no patient is 400', () async {
      final r = await forecast(op, {
        'resourceType': 'Parameters',
        'parameter': [
          {'name': 'assessmentDate', 'valueDate': '2026-10-18'},
        ],
      });
      expect(r.statusCode, 400, reason: await r.readAsString());
    });

    test('$op: a patient that is not a Patient is 400', () async {
      final r = await forecast(op, {
        'resourceType': 'Parameters',
        'parameter': [
          {'name': 'assessmentDate', 'valueDate': '2026-10-18'},
          {
            'name': 'patient',
            'resource': {
              'resourceType': 'Observation',
              'status': 'final',
              'code': {'text': 'x'},
            },
          },
        ],
      });
      expect(r.statusCode, 400, reason: await r.readAsString());
    });

    test('$op: control, a Patient with a birth date is answered', () async {
      final r = await forecast(op, {
        'resourceType': 'Parameters',
        'parameter': [
          {'name': 'assessmentDate', 'valueDate': '2026-10-18'},
          {
            'name': 'patient',
            'resource': {
              'resourceType': 'Patient',
              'id': 'x',
              'birthDate': '2025-01-01',
            },
          },
        ],
      });
      expect(r.statusCode, 200, reason: await r.readAsString());
    });
  }
}
