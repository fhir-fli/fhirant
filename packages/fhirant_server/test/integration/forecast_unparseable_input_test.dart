import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// Found on the phone run of REVIEW-2026-10-17 (2026-10-18). A forecast whose
/// Parameters carried a resource the model cannot read (an Immunization with
/// `occurrenceDateTime: "bad"`) answered 500 "Immunization forecast error":
/// the parse ran inside the handler's catch-all. R4B http.html 3.1.0.4.2,
/// Rejecting Updates (read 2026-10-17, verbatim): "400 Bad Request - resource
/// could not be parsed or failed basic FHIR validation rules"; create says
/// the same. An operation's input is answered the same way here.
///
/// Two readable doses the engine cannot evaluate are refused before it runs,
/// 422, as a Patient with no birthDate is. Cardinalities read 2026-10-18 from
/// the R4B profiles-resources.json snapshot. One dose is dated only as text:
/// Immunization.occurrence[x] is 1..1, dateTime or string, and CDSi Logic
/// Spec v4.6 Tables 3-4 and 6-2 give Date Administered no assumed value; the
/// engine used to date it 2999-01-01. The other has no id:
/// ImmunizationEvaluation.immunizationEvent is 1..1, and the engine names the
/// dose by id; it stopped on a null check and this answered 500.
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

  Map<String, dynamic> withImmunization(
    String occurrence, {
    String? id = 'd1',
    String occurrenceElement = 'occurrenceDateTime',
  }) =>
      {
        'resourceType': 'Parameters',
        'parameter': [
          {'name': 'assessmentDate', 'valueDate': '2026-10-18'},
          {
            'name': 'patient',
            'resource': {
              'resourceType': 'Patient',
              'id': 'p',
              'birthDate': '2025-01-01',
            },
          },
          {
            'name': 'immunization',
            'resource': {
              'resourceType': 'Immunization',
              if (id != null) 'id': id,
              'status': 'completed',
              'vaccineCode': {
                'coding': [
                  {'system': 'http://hl7.org/fhir/sid/cvx', 'code': '08'},
                ],
              },
              'patient': {'reference': 'Patient/p'},
              occurrenceElement: occurrence,
            },
          },
        ],
      };

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
    test('$op: an unreadable resource in the Parameters is 400', () async {
      final r = await forecast(op, withImmunization('bad'));
      final body = await r.readAsString();
      expect(r.statusCode, 400, reason: body);
      expect(
        (jsonDecode(body) as Map)['resourceType'],
        'OperationOutcome',
      );
    });

    test('$op: a dose dated only as text is 422', () async {
      final r = await forecast(
        op,
        withImmunization('spring', occurrenceElement: 'occurrenceString'),
      );
      expect(r.statusCode, 422, reason: await r.readAsString());
    });

    test('$op: a dose with no id is 422', () async {
      final r = await forecast(op, withImmunization('2025-03-01', id: null));
      expect(r.statusCode, 422, reason: await r.readAsString());
    });

    test('$op: control, the same request with a real date', () async {
      final r = await forecast(op, withImmunization('2025-03-01'));
      expect(r.statusCode, 200, reason: await r.readAsString());
    });
  }
}
