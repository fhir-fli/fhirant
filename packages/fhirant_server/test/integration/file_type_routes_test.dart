import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// OWASP ASVS 5.0.0 V5.2.2 (L1; the OWASP ASVS 5.0.0 JSON release, read
/// 2026-10-21): "Verify that when the application accepts a file ... it
/// checks if the file extension matches an expected file extension and
/// validates that the contents correspond to the type represented by the
/// extension. This includes, but is not limited to, checking the initial
/// 'magic bytes'". A FHIR file's extension is its declared type
/// (Binary.contentType, Attachment.contentType, Signature.sigFormat).
///
/// The server here has no scanner, as on the phone: the type is checked
/// anyway.
void main() {
  const json = {
    'content-type': 'application/fhir+json',
    'accept': 'application/fhir+json',
  };
  // The first bytes of a PDF and of a PNG (WHATWG MIME Sniffing §7.1 and
  // §6.1, read 2026-10-21); what follows does not matter to the check.
  final pdf = base64.encode([...latin1.encode('%PDF-1.7\n'), 0x25, 0xE2]);
  final png = base64.encode(
    [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13],
  );
  String text(String s) => base64.encode(utf8.encode(s));

  late FhirAntDb db;
  late Handler handler;

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
    final server = FhirAntServer(db, jwtSecret: testJwtSecret, devMode: true);
    handler = server.createHandler(server.createRouter());
  });

  tearDown(() => db.close());

  Future<Response> send(String method, String path, Object body) async =>
      handler(
        testRequest(method, path, body: jsonEncode(body), headers: json),
      );

  Future<Map<String, dynamic>> bodyOf(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, dynamic>;

  Future<int> stored(String type) async {
    final r = await handler(
      testRequest('GET', '/$type?_summary=count', headers: json),
    );
    return (await bodyOf(r))['total'] as int;
  }

  Map<String, dynamic> binary(String? contentType, String data) => {
        'resourceType': 'Binary',
        if (contentType != null) 'contentType': contentType,
        'data': data,
      };

  Map<String, dynamic> document(String? contentType, String data) => {
        'resourceType': 'DocumentReference',
        'status': 'current',
        'content': [
          {
            'attachment': {
              if (contentType != null) 'contentType': contentType,
              'data': data,
            },
          },
        ],
      };

  Future<void> expectRefused(
    Response r, {
    int status = 422,
    String code = 'business-rule',
    required String says,
  }) async {
    final body = await bodyOf(r);
    expect(r.statusCode, status, reason: '$body');
    final issue = (body['issue'] as List).single as Map;
    expect(issue['code'], code);
    expect('${issue['diagnostics']}', contains(says));
  }

  test('a file whose bytes are its declared type is stored', () async {
    final png1 = await send('POST', '/Binary', binary('image/png', png));
    expect(png1.statusCode, 201);
    final pdf1 = await send(
      'POST',
      '/DocumentReference',
      document('application/pdf', pdf),
    );
    expect(pdf1.statusCode, 201);
    expect(
      (await send(
        'POST',
        '/Binary',
        binary('text/plain; charset=UTF-8', text('Seen today.')),
      ))
          .statusCode,
      201,
    );
  });

  test('bytes that are not the declared type are refused', () async {
    await expectRefused(
      await send('POST', '/Binary', binary('image/png', pdf)),
      says: 'is not image/png',
    );
    await expectRefused(
      await send(
        'POST',
        '/DocumentReference',
        document('application/pdf', png),
      ),
      says: 'is not application/pdf',
    );
    expect(await stored('Binary'), 0);
    expect(await stored('DocumentReference'), 0);
  });

  test('a page declared as text is refused', () async {
    await expectRefused(
      await send(
        'POST',
        '/Binary',
        binary('text/plain', text(' <script>alert(1)</script>')),
      ),
      says: 'is not text/plain',
    );
  });

  test('a type not on the list is refused', () async {
    for (final type in const [
      'text/html',
      'application/xhtml+xml',
      'application/zip',
      'application/octet-stream',
    ]) {
      await expectRefused(
        await send('POST', '/Binary', binary(type, text('x'))),
        says: 'which this server does not store',
      );
    }
    expect(await stored('Binary'), 0);
  });

  test('text in a charset other than UTF-8 is refused', () async {
    await expectRefused(
      await send(
        'POST',
        '/Binary',
        binary('text/plain; charset=ISO-8859-1', text('x')),
      ),
      says: 'only as UTF-8',
    );
  });

  test('data with no type where R4B requires one is 400', () async {
    await expectRefused(
      await send('POST', '/DocumentReference', document(null, pdf)),
      status: 400,
      code: 'invalid',
      says: 'DocumentReference.content.attachment.contentType is required',
    );
  });

  test('an undeclared file is judged by its bytes', () async {
    Map<String, dynamic> patient(String data) => {
          'resourceType': 'Patient',
          'extension': [
            {'url': 'urn:test:file', 'valueBase64Binary': data},
          ],
        };
    expect((await send('POST', '/Patient', patient(png))).statusCode, 201);
    await expectRefused(
      await send('POST', '/Patient', patient(text('<HTML><body>x'))),
      says: 'declares no type',
    );
    expect(await stored('Patient'), 1);
  });

  test('a signature is checked against its sigFormat', () async {
    Map<String, dynamic> provenance(String sigFormat, String data) => {
          'resourceType': 'Provenance',
          'target': [
            {'reference': 'Patient/p1'},
          ],
          'recorded': '2026-10-21T10:00:00Z',
          'agent': [
            {
              'who': {'reference': 'Practitioner/x'},
            },
          ],
          'signature': [
            {
              'type': [
                {
                  'system': 'urn:iso-astm:E1762-95:2013',
                  'code': '1.2.840.10065.1.12.1.1',
                },
              ],
              'when': '2026-10-21T10:00:00Z',
              'who': {'reference': 'Practitioner/x'},
              'sigFormat': sigFormat,
              'data': data,
            },
          ],
        };
    final jws = provenance(
      'application/jose',
      text('eyJhbGciOiJFUzI1NiJ9..c2lnbmF0dXJl'),
    );
    expect((await send('POST', '/Provenance', jws)).statusCode, 201);
    final xml = provenance('application/signature+xml', text('<Signature'));
    await expectRefused(
      await send('POST', '/Provenance', xml),
      says: 'is not application/signature+xml',
    );
  });

  // R4B: Attachment.hash is "Hash of the data (sha-1, base64ed)", not a
  // file. The published documentreference-example.json has one.
  test("an attachment's hash is not checked as a file", () async {
    final r = await send('POST', '/DocumentReference', {
      'resourceType': 'DocumentReference',
      'status': 'current',
      'content': [
        {
          'attachment': {
            'contentType': 'application/pdf',
            'data': pdf,
            'hash': base64.encode(List.generate(20, (i) => i * 13 % 256)),
          },
        },
      ],
    });
    expect(r.statusCode, 201, reason: await r.readAsString());
  });

  test('every Bundle entry is checked', () async {
    final r = await send('POST', '/', {
      'resourceType': 'Bundle',
      'type': 'transaction',
      'entry': [
        {
          'resource': binary('image/png', png),
          'request': {'method': 'POST', 'url': 'Binary'},
        },
        {
          'resource': binary('image/gif', png),
          'request': {'method': 'POST', 'url': 'Binary'},
        },
      ],
    });
    expect(r.statusCode, 422, reason: await r.readAsString());
    expect(await stored('Binary'), 0);
  });
}
