import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// `$backup` hands back the whole database as one passphrase-encrypted
/// SQLite file, streamed; `$restore` takes that file, an encrypted Bundle
/// envelope, or a plain Bundle (REVIEW-2026-09-06 finding 33).
void main() {
  late FhirAntDb db;
  late Handler handler;

  setUp(() async {
    final server = await createTestServer(devMode: true);
    db = server.db;
    handler = server.handler;
    await db.saveResource(
      fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'p1',
        'name': [
          {'family': 'Alpha'},
        ],
      }),
    );
  });

  tearDown(() => db.close());

  Future<Response> backup(Map<String, String> params) async => handler(
        testRequest(
          'POST',
          r'/$backup',
          body: jsonEncode({
            'resourceType': 'Parameters',
            'parameter': [
              for (final e in params.entries)
                {'name': e.key, 'valueString': e.value},
            ],
          }),
          headers: {'content-type': 'application/fhir+json'},
        ),
      );

  test('the default is the encrypted database file, and it restores', () async {
    final r = await backup({'passphrase': 'correct horse'});
    expect(r.statusCode, 200);
    expect(r.headers['content-type'], 'application/vnd.sqlite3');
    expect(r.headers['content-disposition'], contains('.sqlite'));
    final bytes = await r.read().expand((chunk) => chunk).toList();
    expect(int.parse(r.headers['content-length']!), bytes.length);
    expect(String.fromCharCodes(bytes.take(16)), isNot(contains('SQLite')));
    expect(String.fromCharCodes(bytes), isNot(contains('Alpha')));

    final other = await createTestServer(devMode: true);
    addTearDown(other.db.close);
    final restored = await other.handler(
      Request(
        'POST',
        Uri.parse(r'http://localhost:8080/$restore'),
        body: bytes,
        headers: {
          'x-forwarded-for': '127.0.0.1',
          'content-type': 'application/vnd.sqlite3',
          'x-backup-passphrase': 'correct horse',
        },
      ),
    );
    final outcome = jsonDecode(await restored.readAsString());
    expect(restored.statusCode, 200, reason: '$outcome');
    expect(outcome['issue'][0]['diagnostics'], contains('1 saved'));
    final found = await other.db.search(
      resourceType: fhir.R4ResourceType.Patient,
      searchParameters: {
        'family': <String>['Alpha'],
      },
    );
    expect(found, hasLength(1));
  });

  test('a wrong passphrase on the file is refused as such', () async {
    final r = await backup({'passphrase': 'correct horse'});
    final bytes = await r.read().expand((chunk) => chunk).toList();
    final other = await createTestServer(devMode: true);
    addTearDown(other.db.close);
    final restored = await other.handler(
      Request(
        'POST',
        Uri.parse(r'http://localhost:8080/$restore'),
        body: bytes,
        headers: {
          'x-forwarded-for': '127.0.0.1',
          'x-backup-passphrase': 'wrong',
        },
      ),
    );
    final outcome = jsonDecode(await restored.readAsString());
    expect(restored.statusCode, 400, reason: '$outcome');
    expect(outcome['issue'][0]['code'], 'security');
  });

  test('format=bundle still gives the JSON envelope', () async {
    final r = await backup({'passphrase': 'correct horse', 'format': 'bundle'});
    expect(r.statusCode, 200);
    // Content negotiation restates the media type; it is JSON either way.
    expect(r.headers['content-type'], contains('json'));
    final body = await r.readAsString();
    expect(body.trim(), startsWith('{'));
  });

  test('no temporary files are left behind', () async {
    final before = Directory.systemTemp
        .listSync()
        .where((e) => e.path.contains('fhirant-backup-'))
        .length;
    final r = await backup({'passphrase': 'correct horse'});
    await for (final _ in r.read()) {}
    // The directory goes when the stream is done.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final after = Directory.systemTemp
        .listSync()
        .where((e) => e.path.contains('fhirant-backup-'))
        .length;
    expect(after, before);
  });
}
