import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:fhirant_server/src/services/backup_service.dart';
import 'package:fhirant_server/src/services/file_scanner.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../services/fake_clamd.dart';
import 'test_helpers.dart';

/// OWASP ASVS 5.0.0 V5.4.3 (L2; the OWASP ASVS 5.0.0 JSON release, read
/// 2026-10-21): "Verify that files obtained from untrusted sources are
/// scanned by antivirus scanners to prevent serving of known malicious
/// content." A backup sent to `$restore` is such a source: every file in
/// it is scanned before anything is written, in both formats (a Bundle, and
/// the encrypted store copy, whose rows used to be copied by SQL unread).
/// A resource carrying a match is left out and listed as an error, the rest
/// restores (Grey, 2026-10-29); a scanner that cannot answer is 503 with
/// nothing written, as on every route that stores a file (file_refusal.dart).
void main() {
  final infected = base64.encode(latin1.encode(eicar));
  final clean = base64.encode(utf8.encode('a clean file'));
  const passphrase = 'correct horse';

  late FakeClamd clamd;
  late FhirAntDb target;
  late Directory dir;

  Handler serve(FileScanner? scanner) {
    final server = FhirAntServer(
      target,
      jwtSecret: testJwtSecret,
      devMode: true,
      fileScanner: scanner,
    );
    return server.createHandler(server.createRouter());
  }

  Handler scanned() => serve(
        ClamdScanner(
          '127.0.0.1',
          port: clamd.port,
          timeout: const Duration(seconds: 5),
        ),
      );

  setUp(() async {
    clamd = await FakeClamd.start();
    dir = await Directory.systemTemp.createTemp('fhirant_restore_scan_');
    target = FhirAntDb(NativeDatabase.memory());
    await target.initialize();
  });

  tearDown(() async {
    await clamd.close();
    await target.close();
    await dir.delete(recursive: true);
  });

  // Text files, declared as text, so the type check passes them on to the
  // scanner (file_scan_routes_test.dart).
  fhir.Resource binary(String id, String data) => fhir.Resource.fromJson({
        'resourceType': 'Binary',
        'id': id,
        'contentType': 'text/plain',
        'data': data,
      });

  fhir.Resource document(String id, String data) => fhir.Resource.fromJson({
        'resourceType': 'DocumentReference',
        'id': id,
        'status': 'current',
        'content': [
          {
            'attachment': {'contentType': 'text/plain', 'data': data},
          },
        ],
      });

  fhir.Resource library(String data) => fhir.Resource.fromJson({
        'resourceType': 'Library',
        'id': 'lib',
        'url': 'http://example.org/Library/scan',
        'status': 'active',
        'type': {
          'coding': [
            {
              'system': 'http://terminology.hl7.org/CodeSystem/library-type',
              'code': 'logic-library',
            },
          ],
        },
        'content': [
          {'contentType': 'text/plain', 'data': data},
        ],
      });

  Future<Response> restore(Handler handler, List<int> body) async => handler(
        Request(
          'POST',
          Uri.parse(r'http://localhost:8080/$restore'),
          body: body,
          headers: {
            'x-forwarded-for': '127.0.0.1',
            'x-backup-passphrase': passphrase,
          },
        ),
      );

  Future<Map<String, dynamic>> bodyOf(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, dynamic>;

  List<String> diagnostics(Map<String, dynamic> outcome) => [
        for (final issue in outcome['issue'] as List)
          '${(issue as Map)['diagnostics']}',
      ];

  Future<int> rows(FhirAntDb db, String sql) async =>
      (await db.customSelect(sql).getSingle()).data.values.single! as int;

  /// The store holds nothing the restore could have written.
  Future<void> expectNothingRestored() async {
    expect(await rows(target, 'SELECT count(*) FROM resources'), 0);
    expect(await rows(target, 'SELECT count(*) FROM resources_history'), 0);
    expect(await rows(target, 'SELECT count(*) FROM canonical_resources'), 0);
  }

  /// An encrypted store copy, as `$backup` writes it, of a store that took
  /// these resources without a scanner (the phone, or another server).
  Future<List<int>> encryptedBackup() async {
    final source = FhirAntDb(NativeDatabase.memory());
    await source.initialize();
    try {
      await source.saveResource(binary('ok', clean));
      await source.saveResource(binary('bad', infected));
      await source.saveResource(document('doc', infected));
      // A clean current version over an infected one in history.
      await source.saveResource(binary('was-bad', infected));
      await source.saveResource(binary('was-bad', clean));
      // A deletion: its history row must still read as a resource.
      await source.saveResource(binary('gone', clean));
      await source.deleteResource(fhir.R4ResourceType.Binary, 'gone');
      await source.saveResource(library(infected));
      // The canonical store is written on its own (fhir_db's
      // saveCanonicalResource), not by saveResource.
      await source.fhirDao.saveCanonicalResource(library(infected));
      expect(
        await rows(source, 'SELECT count(*) FROM canonical_resources'),
        1,
        reason: 'the Library is in the canonical store',
      );
      final file = await BackupService.createFile(
        source,
        passphrase,
        '${dir.path}/backup.sqlite',
      );
      return await file.readAsBytes();
    } finally {
      await source.close();
    }
  }

  test('a Bundle backup: the infected entries are left out, the rest restores',
      () async {
    final bundle = jsonEncode({
      'resourceType': 'Bundle',
      'type': 'collection',
      'entry': [
        for (final r in [
          binary('ok', clean),
          binary('bad', infected),
          document('doc', infected),
        ])
          {'resource': r.toJson()},
      ],
    });
    final r = await restore(scanned(), utf8.encode(bundle));
    final outcome = await bodyOf(r);
    expect(r.statusCode, 200, reason: '$outcome');
    final text = diagnostics(outcome);
    expect(text.first, contains('1 saved, 2 errors'));
    expect(
      text.where((t) => t.contains('Binary/bad')).single,
      contains('Eicar-Test-Signature'),
    );
    expect(
      text.where((t) => t.contains('DocumentReference/doc')).single,
      contains('Eicar-Test-Signature'),
    );
    expect(
      await target.getResource(fhir.R4ResourceType.Binary, 'ok'),
      isNotNull,
    );
    expect(await target.getResource(fhir.R4ResourceType.Binary, 'bad'), isNull);
    expect(
      await target.getResource(fhir.R4ResourceType.DocumentReference, 'doc'),
      isNull,
    );
  });

  test(
      'an encrypted backup: every infected row is left out, current, '
      'history and canonical', () async {
    final r = await restore(scanned(), await encryptedBackup());
    final outcome = await bodyOf(r);
    expect(r.statusCode, 200, reason: '$outcome');
    final text = diagnostics(outcome);
    // The tombstone parsed; nothing was left out for being unreadable.
    expect(text.where((t) => t.contains('not a readable')), isEmpty);
    for (final key in [
      'Binary/bad (resources)',
      'DocumentReference/doc (resources)',
      'Binary/was-bad (resources_history)',
      'Library/lib (resources)',
      'Library/lib (canonical_resources)',
    ]) {
      expect(
        text.where((t) => t.contains(key)).single,
        contains('Eicar-Test-Signature'),
        reason: key,
      );
    }
    expect(
      await target.getResource(fhir.R4ResourceType.Binary, 'ok'),
      isNotNull,
    );
    expect(await target.getResource(fhir.R4ResourceType.Binary, 'bad'), isNull);
    expect(
      await target.getResource(fhir.R4ResourceType.DocumentReference, 'doc'),
      isNull,
    );
    expect(
      await target.getResource(fhir.R4ResourceType.Library, 'lib'),
      isNull,
    );
    expect(await rows(target, 'SELECT count(*) FROM canonical_resources'), 0);
    // The clean current version restores; its infected first version does
    // not.
    final history = await target.getResourceHistory(
      fhir.R4ResourceType.Binary,
      'was-bad',
    );
    expect([for (final h in history) h.meta!.versionId!.valueString], ['2']);
    // No index row of a left-out resource came across with the backup's.
    for (final table in FhirDb.searchTableNames) {
      expect(
        await rows(
          target,
          "SELECT count(*) FROM $table WHERE id IN ('bad', 'doc', 'lib') "
          "OR id LIKE 'Binary/bad#%'",
        ),
        0,
        reason: table,
      );
    }
  });

  for (final kind in ['a Bundle', 'an encrypted']) {
    test('$kind backup with the scanner down: 503, nothing restored', () async {
      final body = kind == 'a Bundle'
          ? utf8.encode(
              jsonEncode({
                'resourceType': 'Bundle',
                'type': 'collection',
                'entry': [
                  {'resource': binary('ok', clean).toJson()},
                ],
              }),
            )
          : await encryptedBackup();
      clamd.mode = ClamdMode.hangUp;
      final r = await restore(scanned(), body);
      final outcome = await bodyOf(r);
      expect(r.statusCode, 503, reason: '$outcome');
      final issue = (outcome['issue'] as List).single as Map;
      expect(issue['code'], 'transient');
      expect('${issue['diagnostics']}', contains('Nothing was restored'));
      await expectNothingRestored();
    });
  }

  test('with no scanner configured, a backup restores as before', () async {
    final r = await restore(serve(null), await encryptedBackup());
    expect(r.statusCode, 200, reason: await r.readAsString());
    expect(
      await target.getResource(fhir.R4ResourceType.Binary, 'bad'),
      isNotNull,
    );
    expect(clamd.streams, isEmpty);
  });
}
