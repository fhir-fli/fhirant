import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/resource_handler.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// R4 3.1.1.4.4: "Server SHALL reject any search request that contains is
/// suffixed by a modifier that the server does not support for that parameter
/// ... using an HTTP 400 error with an OperationOutcome with a clear error
/// message."
///
/// Contrast an unknown PARAMETER, which the same page says a server SHOULD
/// ignore. Ignoring a parameter only widens the result set and the self link
/// discloses it. Ignoring a modifier silently changes what the query means.
void main() {
  late FhirAntDb db;

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    await db.saveResource(
      fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'p1',
        'gender': 'male',
        'name': [
          {'family': 'Faulkenberry'},
        ],
      }),
    );
  });
  tearDown(() async => db.close());

  Future<Response> search(String query) => getResourcesHandler(
        Request('GET', Uri.parse('http://localhost:8080/Patient?$query')),
        'Patient',
        db,
      );

  test('a plain search still works, so a 400 below is the modifier', () async {
    final response = await search('family=Faulkenberry');
    expect(response.statusCode, equals(200));
  });

  test('a string modifier on a token parameter is 400', () async {
    final response = await search('gender:exact=male');
    expect(response.statusCode, equals(400));
  });

  test('the body is an OperationOutcome naming the problem', () async {
    final response = await search('gender:contains=male');
    final body =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(body['resourceType'], equals('OperationOutcome'));
    final issue = (body['issue'] as List).first as Map<String, dynamic>;
    expect(issue['severity'], equals('error'));
    expect(issue['code'], equals('not-supported'));
    expect(issue['diagnostics'], contains('gender'));
    expect(issue['diagnostics'], contains('token'));
  });

  test('an invented modifier is 400', () async {
    expect((await search('family:banana=x')).statusCode, equals(400));
  });

  test('a modifier the type allows is not rejected', () async {
    expect((await search('family:exact=Faulkenberry')).statusCode, equals(200));
    expect((await search('gender:not=female')).statusCode, equals(200));
    expect((await search('family:missing=false')).statusCode, equals(200));
  });

  test('an unknown parameter is ignored, not rejected', () async {
    // The spec's asymmetry: SHOULD ignore an unknown parameter, SHALL reject
    // an unsupported modifier.
    expect((await search('notAParameter=x')).statusCode, equals(200));
  });
}
