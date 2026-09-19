import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' show R4ResourceType;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-17 A10: a 20 MB Patient was accepted (201). Every write
/// route reads its body whole (`request.readAsString()`), and on a phone
/// that is memory. One middleware caps the body, before authentication,
/// with 413; a body that declares its length is refused from the header,
/// one that does not is refused as soon as the cap is passed. `$restore`
/// streams its body to disk by design and is not capped here.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;
  const cap = 64 * 1024;

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
    final server = FhirAntServer(
      db,
      jwtSecret: testJwtSecret,
      maxRequestBody: cap,
    );
    handler = server.createHandler(server.createRouter());
    token = await issueTestToken(db, role: 'admin', scopes: ['system/*.*']);
  });
  tearDown(() => db.close());

  String patientOf(int bytes) {
    final padding = 'x' * bytes;
    return '{"resourceType":"Patient","id":"p","name":[{"text":"$padding"}]}';
  }

  Future<Response> put(String body, {bool declareLength = true}) async =>
      handler(
        Request(
          'PUT',
          Uri.parse('http://localhost/Patient/p'),
          body: declareLength ? body : Stream.value(utf8.encode(body)),
          headers: {
            'content-type': 'application/fhir+json',
            'authorization': 'Bearer $token',
            if (declareLength) 'content-length': '${utf8.encode(body).length}',
          },
        ),
      );

  test('a body under the cap is accepted', () async {
    final res = await put(patientOf(cap ~/ 2));
    expect(res.statusCode, 201, reason: await res.readAsString());
  });

  test('a body over the cap is 413, with or without Content-Length', () async {
    for (final declared in [true, false]) {
      final res = await put(patientOf(cap * 2), declareLength: declared);
      final text = await res.readAsString();
      expect(res.statusCode, 413, reason: 'declared=$declared: $text');
      final json = jsonDecode(text) as Map<String, dynamic>;
      expect(json['resourceType'], 'OperationOutcome');
      expect(await db.getResource(R4ResourceType.Patient, 'p'), isNull);
    }
  });

  test('a body over the cap is refused before authentication', () async {
    final res = await handler(
      Request(
        'PUT',
        Uri.parse('http://localhost/Patient/p'),
        body: patientOf(cap * 2),
        headers: {'content-type': 'application/fhir+json'},
      ),
    );
    expect(res.statusCode, 413);
  });

  test(r'$restore is not capped here', () async {
    final res = await handler(
      Request(
        'POST',
        Uri.parse(r'http://localhost/$restore'),
        body: 'x' * (cap * 2),
        headers: {
          'content-type': 'application/vnd.sqlite3',
          'authorization': 'Bearer $token',
        },
      ),
    );
    // Refused for what it is, not for its size.
    expect(res.statusCode, isNot(413));
  });
}
