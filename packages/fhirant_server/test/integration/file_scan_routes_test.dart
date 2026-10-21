import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:fhirant_server/src/services/file_scanner.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../services/fake_clamd.dart';
import 'test_helpers.dart';

/// OWASP ASVS 5.0.0 V5.4.3 (L2; the OWASP ASVS 5.0.0 JSON release, read
/// 2026-10-21): "Verify that files obtained from untrusted sources are
/// scanned by antivirus scanners to prevent serving of known malicious
/// content." Every route that stores a client's resource is asked to store
/// the EICAR test file, and must refuse it with 422 (R4B http.html, create,
/// read 2026-10-21: "When the server rejects the content of the resource
/// because of business rules ... 422"), storing nothing. With the scanner
/// down the file is refused too (503); with no scanner configured nothing
/// changes.
void main() {
  const json = {
    'content-type': 'application/fhir+json',
    'accept': 'application/fhir+json',
  };
  final infected = base64.encode(latin1.encode(eicar));
  final clean = base64.encode(utf8.encode('a clean file'));

  late FakeClamd clamd;
  late FhirAntDb db;
  late Handler handler;

  Handler serve(FileScanner? scanner) {
    final server = FhirAntServer(
      db,
      jwtSecret: testJwtSecret,
      devMode: true,
      fileScanner: scanner,
    );
    return server.createHandler(server.createRouter());
  }

  setUp(() async {
    clamd = await FakeClamd.start();
    db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
    handler = serve(
      ClamdScanner(
        '127.0.0.1',
        port: clamd.port,
        timeout: const Duration(seconds: 5),
      ),
    );
  });

  tearDown(() async {
    await clamd.close();
    await db.close();
  });

  Future<Response> send(
    String method,
    String path,
    Object body, {
    Map<String, String> headers = json,
  }) async =>
      handler(
        testRequest(method, path, body: jsonEncode(body), headers: headers),
      );

  Future<Map<String, dynamic>> bodyOf(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, dynamic>;

  Future<int> stored(String type) async {
    final r = await handler(
      testRequest('GET', '/$type?_summary=count', headers: json),
    );
    return (await bodyOf(r))['total'] as int;
  }

  Map<String, dynamic> binary(String data, {String? id}) => {
        'resourceType': 'Binary',
        if (id != null) 'id': id,
        'contentType': 'application/octet-stream',
        'data': data,
      };

  Map<String, dynamic> document(String data) => {
        'resourceType': 'DocumentReference',
        'status': 'current',
        'identifier': [
          {'system': 'urn:test', 'value': 'doc-1'},
        ],
        'content': [
          {
            'attachment': {'contentType': 'application/pdf', 'data': data},
          },
        ],
      };

  Future<void> expectRefused(Response r) async {
    final body = await bodyOf(r);
    expect(r.statusCode, 422, reason: '$body');
    final issue = (body['issue'] as List).single as Map;
    expect(issue['code'], 'business-rule');
    expect('${issue['diagnostics']}', contains('Eicar-Test-Signature'));
  }

  test('create', () async {
    await expectRefused(await send('POST', '/Binary', binary(infected)));
    expect(await stored('Binary'), 0);
    expect((await send('POST', '/Binary', binary(clean))).statusCode, 201);
  });

  test('conditional create', () async {
    await expectRefused(
      await send(
        'POST',
        '/DocumentReference',
        document(infected),
        headers: {...json, 'if-none-exist': 'identifier=urn:test|doc-1'},
      ),
    );
    expect(await stored('DocumentReference'), 0);
  });

  test('update', () async {
    await expectRefused(
      await send('PUT', '/Binary/b1', binary(infected, id: 'b1')),
    );
    expect(await stored('Binary'), 0);
  });

  test('conditional update', () async {
    await expectRefused(
      await send(
        'PUT',
        '/DocumentReference?identifier=urn:test|doc-1',
        document(infected),
      ),
    );
    expect(await stored('DocumentReference'), 0);
  });

  test('PATCH that adds a file', () async {
    final created = await send('POST', '/DocumentReference', document(clean));
    final id = (await bodyOf(created))['id'];
    final r = await send(
      'PATCH',
      '/DocumentReference/$id',
      [
        {
          'op': 'replace',
          'path': '/content/0/attachment/data',
          'value': infected,
        },
      ],
      headers: {...json, 'content-type': 'application/json-patch+json'},
    );
    await expectRefused(r);
    final now = await handler(
      testRequest('GET', '/DocumentReference/$id', headers: json),
    );
    expect(
      (((await bodyOf(now))['content'] as List).single as Map)['attachment'],
      containsPair('data', clean),
    );
  });

  test("a file in a primitive's own extension", () async {
    await expectRefused(
      await send('POST', '/Patient', {
        'resourceType': 'Patient',
        'birthDate': '1970-01-01',
        '_birthDate': {
          'extension': [
            {'url': 'http://example.org/f', 'valueBase64Binary': infected},
          ],
        },
      }),
    );
    expect(await stored('Patient'), 0);
  });

  test('transaction: the whole Bundle is refused, nothing stored', () async {
    final r = await send('POST', '/', {
      'resourceType': 'Bundle',
      'type': 'transaction',
      'entry': [
        {
          'resource': {'resourceType': 'Patient'},
          'request': {'method': 'POST', 'url': 'Patient'},
        },
        {
          'resource': binary(infected),
          'request': {'method': 'POST', 'url': 'Binary'},
        },
      ],
    });
    final body = await bodyOf(r);
    expect(r.statusCode, 422, reason: '$body');
    expect('$body', contains('Eicar-Test-Signature'));
    expect(await stored('Patient'), 0);
    expect(await stored('Binary'), 0);
  });

  test('transaction: a PATCH entry that adds a file', () async {
    final created = await send('POST', '/DocumentReference', document(clean));
    final id = (await bodyOf(created))['id'];
    final patch = jsonEncode([
      {
        'op': 'replace',
        'path': '/content/0/attachment/data',
        'value': infected,
      },
    ]);
    final r = await send('POST', '/', {
      'resourceType': 'Bundle',
      'type': 'transaction',
      'entry': [
        {
          'resource': {
            'resourceType': 'Binary',
            'contentType': 'application/json-patch+json',
            'data': base64.encode(utf8.encode(patch)),
          },
          'request': {'method': 'PATCH', 'url': 'DocumentReference/$id'},
        },
      ],
    });
    final body = await bodyOf(r);
    expect(r.statusCode, 422, reason: '$body');
    expect('$body', contains('Eicar-Test-Signature'));
  });

  test('batch: only the entry with the file is refused', () async {
    final r = await send('POST', '/', {
      'resourceType': 'Bundle',
      'type': 'batch',
      'entry': [
        {
          'resource': {'resourceType': 'Patient'},
          'request': {'method': 'POST', 'url': 'Patient'},
        },
        {
          'resource': binary(infected),
          'request': {'method': 'POST', 'url': 'Binary'},
        },
      ],
    });
    final body = await bodyOf(r);
    expect(r.statusCode, 200, reason: '$body');
    final statuses = [
      for (final e in body['entry'] as List)
        ((e as Map)['response'] as Map)['status'],
    ];
    expect(statuses, ['201', '422']);
    expect(await stored('Patient'), 1);
    expect(await stored('Binary'), 0);
  });

  test('scanner down: refused with 503, nothing stored', () async {
    final free = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = free.port;
    await free.close();
    handler = serve(
      ClamdScanner(
        '127.0.0.1',
        port: port,
        timeout: const Duration(seconds: 2),
      ),
    );
    final r = await send('POST', '/Binary', binary(clean));
    final body = await bodyOf(r);
    expect(r.statusCode, 503, reason: '$body');
    expect(((body['issue'] as List).single as Map)['code'], 'transient');
    expect('$body', isNot(contains('$port')));
    expect(await stored('Binary'), 0);
  });

  test('no scanner configured: stored as before', () async {
    handler = serve(null);
    expect((await send('POST', '/Binary', binary(infected))).statusCode, 201);
    expect(clamd.streams, isEmpty);
  });
}
