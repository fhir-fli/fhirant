import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-17 C5. `PUT /Patient/a$b_c` was a 201. R4B datatypes.html
/// `id`, verbatim: "Regex: [A-Za-z0-9\-\.]{1,64}". A client-supplied id
/// outside it is a 400, and one inside it still creates.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;
  late Directory exportDir;

  setUp(() async {
    exportDir = await Directory.systemTemp.createTemp('put-id');
    final server = await createTestServer(exportDir: exportDir.path);
    db = server.db;
    handler = server.handler;
    token = await issueTestToken(
      db,
      username: 'admin',
      role: 'admin',
      scopes: ['system/*.*'],
    );
  });

  tearDown(() async {
    await db.close();
    await exportDir.delete(recursive: true);
  });

  Future<int> put(String id) async {
    final r = await handler(
      testRequest(
        'PUT',
        '/Patient/${Uri.encodeComponent(id)}',
        authToken: token,
        headers: {'content-type': 'application/fhir+json'},
        body: jsonEncode({'resourceType': 'Patient', 'id': id}),
      ),
    );
    return r.statusCode;
  }

  test('an id outside the grammar is refused', () async {
    for (final bad in [r'a$b_c', 'a b', 'ü', 'x' * 65]) {
      expect(await put(bad), 400, reason: bad);
      expect(await db.getResource(fhir.R4ResourceType.Patient, bad), isNull);
    }
  });

  test('an id inside the grammar creates', () async {
    for (final good in ['p1', 'A-b.C', '1.2.840.113619', 'x' * 64]) {
      expect(await put(good), 201, reason: good);
    }
  });
}
