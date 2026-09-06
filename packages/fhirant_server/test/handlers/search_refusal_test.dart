import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/compartment_handler.dart';
import 'package:fhirant_server/src/handlers/resource_handler.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// The store refuses a search three ways, and each has to reach the client as
/// a 400 with an OperationOutcome rather than a 500 or an empty bundle.
///
/// R4B 3.1.1.3: "Where the content of the parameter is syntactically
/// incorrect, servers SHOULD return an error. However, where the issue is a
/// logical condition (e.g. unknown subject or code), the server SHOULD process
/// the search … with the result of returning an empty search set". An invalid
/// date used to be answered with an empty bundle: the client was told there
/// were no such records when the question had not been understood.
///
/// R4B 3.1.1.4.12: "Servers SHOULD reject a search where the logical id refers
/// to more than one matching resource across different types."
void main() {
  late FhirAntDb db;

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    await db.saveResource(
      fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'shared',
        'birthDate': '1980-02-03',
      }),
    );
    await db.saveResource(
      fhir.FhirGroup.fromJson({
        'resourceType': 'Group',
        'id': 'shared',
        'type': 'person',
        'actual': true,
      }),
    );
    await db.saveResource(
      fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': 'o1',
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '8867-4'},
          ],
        },
        'subject': {'reference': 'Patient/shared'},
        'effectiveDateTime': '2024-05-06',
      }),
    );
    // A second Observation whose subject is the Group with the same id. The
    // store judges ambiguity over the types the id is REFERENCED as, which is
    // the spec's "more than one matching resource across different types".
    await db.saveResource(
      fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': 'o2',
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '8867-4'},
          ],
        },
        'subject': {'reference': 'Group/shared'},
      }),
    );
  });
  tearDown(() async => db.close());

  Future<Response> get(String type, String query) => getResourcesHandler(
        Request('GET', Uri.parse('http://localhost:8080/$type?$query')),
        type,
        db,
      );

  Future<Map<String, dynamic>> outcome(Response response) async {
    expect(response.statusCode, equals(400));
    final body =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(body['resourceType'], equals('OperationOutcome'));
    return (body['issue'] as List).first as Map<String, dynamic>;
  }

  test('a date that is not a date is 400 invalid, not an empty bundle',
      () async {
    final issue = await outcome(await get('Patient', 'birthdate=23 May 2009'));
    expect(issue['code'], equals('invalid'));
    expect(issue['diagnostics'], contains('birthdate'));
    expect(issue['diagnostics'], contains('23 May 2009'));
  });

  test('a valid date on the same parameter is 200, so the 400 is the value',
      () async {
    expect((await get('Patient', 'birthdate=1980-02-03')).statusCode, 200);
  });

  test('a number that is not a number is 400 invalid', () async {
    final issue = await outcome(await get('Observation', 'date=gtyesterday'));
    expect(issue['code'], equals('invalid'));
  });

  test('a bare id that names two resource types is 400', () async {
    // Patient/shared and Group/shared both exist; `subject` can point at
    // either. The store cannot know which the client meant.
    final issue = await outcome(await get('Observation', 'subject=shared'));
    expect(issue['code'], equals('invalid'));
    expect(issue['diagnostics'], contains('Patient'));
    expect(issue['diagnostics'], contains('Group'));
    expect(issue['diagnostics'], contains('Give the type'));
  });

  test('the typed spelling of that reference is 200', () async {
    final response = await get('Observation', 'subject=Patient/shared');
    expect(response.statusCode, equals(200));
    final body =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect((body['entry'] as List).length, equals(1));
  });

  test('POST _search maps the same refusals', () async {
    final response = await postSearchHandler(
      Request(
        'POST',
        Uri.parse('http://localhost:8080/Patient/_search'),
        body: 'birthdate=notadate',
        headers: {'content-type': 'application/x-www-form-urlencoded'},
      ),
      'Patient',
      db,
    );
    final issue = await outcome(response);
    expect(issue['code'], equals('invalid'));
  });

  test('system-level POST _search maps the same refusals', () async {
    final response = await postSystemSearchHandler(
      Request(
        'POST',
        Uri.parse('http://localhost:8080/_search'),
        body: '_type=Patient&birthdate=notadate',
        headers: {'content-type': 'application/x-www-form-urlencoded'},
      ),
      db,
    );
    final issue = await outcome(response);
    expect(issue['code'], equals('invalid'));
  });

  test('a compartment search with an invalid value is 400, not 500', () async {
    final response = await compartmentSearchHandler(
      Request(
        'GET',
        Uri.parse(
          'http://localhost:8080/Patient/shared/Observation?date=notadate',
        ),
      ),
      'Patient',
      'shared',
      'Observation',
      db,
    );
    final issue = await outcome(response);
    expect(issue['code'], equals('invalid'));
  });

  test('If-None-Exist with an invalid value is 400 naming the header',
      () async {
    final response = await postResourceHandler(
      Request(
        'POST',
        Uri.parse('http://localhost:8080/Patient'),
        body: jsonEncode({'resourceType': 'Patient', 'id': 'new-1'}),
        headers: {
          'content-type': 'application/fhir+json',
          'If-None-Exist': 'birthdate=notadate',
        },
      ),
      'Patient',
      db,
    );
    final issue = await outcome(response);
    expect(issue['code'], equals('invalid'));
    expect(issue['diagnostics'], contains('If-None-Exist'));
    // Nothing was created.
    expect(await db.getResource(fhir.R4ResourceType.Patient, 'new-1'), isNull);
  });
}
