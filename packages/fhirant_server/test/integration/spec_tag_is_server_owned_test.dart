import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/spec_loader.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-17 S3. `$backup` and a system `$export` leave out every
/// resource carrying the `spec` tag, and a client could write that tag: a
/// clinician PUT a Patient with it and the backup restored 1 of 2 patients.
/// The tag is the server's. No client write, by any route, adds it or keeps
/// it; the specification load alone writes it.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String admin;
  late String clinician;

  const specCoding = {'system': specTagSystem, 'code': specTagCode};
  const otherCoding = {'system': 'urn:ward', 'code': 'west'};

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    admin = await issueTestToken(
      db,
      username: 's3-admin',
      role: 'admin',
      scopes: ['system/*.*'],
    );
    clinician = await issueTestToken(
      db,
      username: 's3-clin',
      scopes: ['user/*.cruds'],
    );
  });
  tearDown(() => db.close());

  Future<Response> send(
    String method,
    String path, {
    Object? body,
    String? token,
    Map<String, String>? headers,
  }) async =>
      handler(
        testRequest(
          method,
          path,
          body: body == null
              ? null
              : body is String
                  ? body
                  : jsonEncode(body),
          headers: {'content-type': 'application/fhir+json', ...?headers},
          authToken: token ?? clinician,
        ),
      );

  Map<String, dynamic> patient(String id, {List<Map<String, String>>? tags}) =>
      {
        'resourceType': 'Patient',
        'id': id,
        'name': [
          {'family': 'Family-$id'},
        ],
        if (tags != null) 'meta': {'tag': tags},
      };

  Future<bool> storedAsSpec(String id) async => isSpecResource(
        (await db.getResource(fhir.R4ResourceType.Patient, id))!,
      );

  Future<int> patientsInARestoredBackup() async {
    final backup = await send(
      'POST',
      r'/$backup',
      token: admin,
      body: {
        'resourceType': 'Parameters',
        'parameter': [
          {'name': 'passphrase', 'valueString': 'a long test passphrase'},
          {'name': 'format', 'valueCode': 'bundle'},
        ],
      },
    );
    expect(backup.statusCode, 200);
    final fresh = await createTestServer();
    try {
      final restore = await fresh.handler(
        testRequest(
          'POST',
          r'/$restore',
          body: await backup.readAsString(),
          headers: {'x-backup-passphrase': 'a long test passphrase'},
          authToken: await issueTestToken(
            fresh.db,
            username: 'r-admin',
            role: 'admin',
            scopes: ['system/*.*'],
          ),
        ),
      );
      expect(restore.statusCode, 200, reason: await restore.readAsString());
      return await fresh.db
          .searchCount(resourceType: fhir.R4ResourceType.Patient);
    } finally {
      await fresh.db.close();
    }
  }

  test('PUT with the tag: stored without it, the other tag kept, backed up',
      () async {
    final kept = await send('PUT', '/Patient/kept', body: patient('kept'));
    expect(kept.statusCode, 201);
    final res = await send(
      'PUT',
      '/Patient/tagged',
      body: patient('tagged', tags: [specCoding, otherCoding]),
    );
    expect(res.statusCode, 201);
    expect(await storedAsSpec('tagged'), isFalse);
    final stored = await db.getResource(fhir.R4ResourceType.Patient, 'tagged');
    expect(
      stored!.meta!.tag!.map((t) => '${t.system}|${t.code}'),
      ['urn:ward|west'],
    );
    expect(await patientsInARestoredBackup(), 2);
  });

  test('POST with the tag: stored without it', () async {
    final res = await send(
      'POST',
      '/Patient',
      body: patient('ignored', tags: [specCoding])..remove('id'),
    );
    expect(res.statusCode, 201);
    final created =
        jsonDecode(await res.readAsString()) as Map<String, dynamic>;
    expect(await storedAsSpec(created['id'] as String), isFalse);
  });

  test(r'$meta-add cannot add it', () async {
    await send('PUT', '/Patient/p1', body: patient('p1'));
    final res = await send(
      'POST',
      r'/Patient/p1/$meta-add',
      body: {
        'resourceType': 'Parameters',
        'parameter': [
          {
            'name': 'meta',
            'valueMeta': {
              'tag': [specCoding, otherCoding],
            },
          },
        ],
      },
    );
    expect(res.statusCode, 200, reason: await res.readAsString());
    expect(await storedAsSpec('p1'), isFalse);
  });

  test('a transaction Bundle cannot add it', () async {
    final res = await send(
      'POST',
      '/',
      body: {
        'resourceType': 'Bundle',
        'type': 'transaction',
        'entry': [
          {
            'resource': patient('in-bundle', tags: [specCoding]),
            'request': {'method': 'PUT', 'url': 'Patient/in-bundle'},
          },
        ],
      },
    );
    expect(res.statusCode, 200, reason: await res.readAsString());
    expect(await storedAsSpec('in-bundle'), isFalse);
  });

  test('JSON Patch cannot add it', () async {
    await send('PUT', '/Patient/p1', body: patient('p1', tags: [otherCoding]));
    final res = await send(
      'PATCH',
      '/Patient/p1',
      headers: {'content-type': 'application/json-patch+json'},
      body: [
        {'op': 'add', 'path': '/meta/tag/-', 'value': specCoding},
      ],
    );
    expect(res.statusCode, 200, reason: await res.readAsString());
    expect(await storedAsSpec('p1'), isFalse);
  });

  test('the specification load writes it, and the backup leaves it out',
      () async {
    await send('PUT', '/Patient/kept', body: patient('kept'));
    final (loaded, errors) = await loadSpecLines(
      db,
      Stream.value(jsonEncode(patient('from-spec'))),
      'test.ndjson',
    );
    expect((loaded, errors), (1, 0));
    expect(await storedAsSpec('from-spec'), isTrue);
    expect(await patientsInARestoredBackup(), 1);
  });

  test(
      'a client write over a specification resource makes it the '
      "deployment's: the tag goes and the backup holds it", () async {
    await loadSpecLines(
      db,
      Stream.value(jsonEncode(patient('from-spec'))),
      'test.ndjson',
    );
    final res = await send(
      'PUT',
      '/Patient/from-spec',
      body: patient('from-spec')..['gender'] = 'female',
    );
    expect(res.statusCode, 200, reason: await res.readAsString());
    expect(await storedAsSpec('from-spec'), isFalse);
    expect(await patientsInARestoredBackup(), 1);
  });
}
