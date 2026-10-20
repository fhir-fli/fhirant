import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// R4B binary.html (hl7.org/fhir/R4B/binary.html, read 2026-10-18,
/// verbatim): securityContext "identifies another resource that can be used
/// as a proxy of the security sensitivity to use when deciding and enforcing
/// access control rules for the Binary resource ... E.g. to identify that
/// the binary resource relates to a patient, and access should only be
/// granted to applications that have access to the patient"; and, under
/// Security Considerations, the client "uses the securityContext element
/// ... to inform the server that the Binary resource should be treated as
/// if it was the other resource."
///
/// Binary is in no Patient CompartmentDefinition, so a patient-scoped token
/// got 404 on every Binary, its own patient's included (found 2026-10-18
/// while fixing REVIEW-2026-10-17's Bulk Binary item).
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String p1;
  late String clinician;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    p1 = await issueTestToken(
      db,
      username: 'patient-one',
      scopes: ['patient/*.cruds'],
      patientId: 'p1',
    );
    clinician = await issueTestToken(
      db,
      username: 'binary-clinician',
      scopes: ['user/*.cruds'],
    );
    for (final r in <Map<String, dynamic>>[
      {'resourceType': 'Patient', 'id': 'p1'},
      {'resourceType': 'Patient', 'id': 'p2'},
      for (final (id, patient) in [('d1', 'p1'), ('d2', 'p2')])
        {
          'resourceType': 'DocumentReference',
          'id': id,
          'status': 'current',
          'subject': {'reference': 'Patient/$patient'},
          'content': [
            {
              'attachment': {'contentType': 'text/plain', 'url': 'Binary/x'},
            },
          ],
        },
      for (final (id, context) in [
        ('b-own', 'Patient/p1'),
        ('b-doc', 'DocumentReference/d1'),
        ('b-other', 'Patient/p2'),
        ('b-otherdoc', 'DocumentReference/d2'),
        ('b-none', null),
        ('b-loop', 'Binary/b-own'),
      ])
        binary(id, context),
    ]) {
      await db.saveResource(fhir.Resource.fromJson(r));
    }
  });

  tearDown(() => db.close());

  Future<Response> send(
    String method,
    String path,
    String token, {
    Map<String, dynamic>? body,
  }) async =>
      handler(
        testRequest(
          method,
          path,
          authToken: token,
          body: body == null ? null : jsonEncode(body),
          headers: {
            'accept': 'application/fhir+json',
            if (body != null) 'content-type': 'application/fhir+json',
          },
        ),
      );

  Future<int> status(
    String method,
    String path,
    String token, {
    Map<String, dynamic>? body,
  }) async =>
      (await send(method, path, token, body: body)).statusCode;

  test('the patient reads a Binary whose context is them or their record',
      () async {
    expect(await status('GET', '/Binary/b-own', p1), 200);
    expect(await status('GET', '/Binary/b-doc', p1), 200);
  });

  test("another patient's Binary is answered as absent", () async {
    for (final id in ['b-other', 'b-otherdoc', 'b-none', 'b-loop']) {
      final r = await send('GET', '/Binary/$id', p1);
      expect(r.statusCode, 404, reason: id);
    }
  });

  test('history follows the same rule', () async {
    expect(await status('GET', '/Binary/b-doc/_history', p1), 200);
    expect(await status('GET', '/Binary/b-other/_history', p1), 404);
  });

  test('the patient creates a Binary in their own context only', () async {
    expect(
      await status('POST', '/Binary', p1, body: binary(null, 'Patient/p1')),
      201,
    );
    expect(
      await status(
        'POST',
        '/Binary',
        p1,
        body: binary(null, 'DocumentReference/d1'),
      ),
      201,
    );
    expect(
      await status('POST', '/Binary', p1, body: binary(null, 'Patient/p2')),
      403,
    );
    expect(
      await status(
        'POST',
        '/Binary',
        p1,
        body: binary(null, 'DocumentReference/d2'),
      ),
      403,
    );
    expect(await status('POST', '/Binary', p1, body: binary(null)), 403);
  });

  test('an update may not move a Binary out of, or into, the context',
      () async {
    expect(
      await status(
        'PUT',
        '/Binary/b-own',
        p1,
        body: binary('b-own', 'Patient/p2'),
      ),
      403,
    );
    expect(
      await status(
        'PUT',
        '/Binary/b-other',
        p1,
        body: binary('b-other', 'Patient/p1'),
      ),
      403,
    );
    expect(
      await status(
        'PUT',
        '/Binary/b-own',
        p1,
        body: binary('b-own', 'DocumentReference/d1'),
      ),
      200,
    );
  });

  test("the patient deletes their own Binary, not another's", () async {
    expect(await status('DELETE', '/Binary/b-other', p1), 403);
    expect(
      await status('DELETE', '/Binary/b-doc', p1),
      anyOf(200, 204),
    );
  });

  test('control: a clinician with user scopes reads any Binary', () async {
    for (final id in ['b-own', 'b-other', 'b-none', 'b-loop']) {
      expect(await status('GET', '/Binary/$id', clinician), 200, reason: id);
    }
  });
}

Map<String, dynamic> binary(String? id, [String? context]) => {
      'resourceType': 'Binary',
      if (id != null) 'id': id,
      'contentType': 'text/plain',
      'data': base64Encode(utf8.encode('content of ${id ?? 'new'}')),
      if (context != null) 'securityContext': {'reference': context},
    };
