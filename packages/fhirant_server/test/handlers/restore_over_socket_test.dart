import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/backup_handler.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

/// `$backup` and `$restore` through a real socket.
///
/// Every other handler test builds a shelf `Request` in process, whose body
/// is a `Stream<List<int>>`. Behind `dart:io` the body arrives as a
/// `Stream<Uint8List>`, and `restoreHandler` piped it into a file sink:
/// "type `_IOSinkImpl` is not a subtype of type
/// `StreamConsumer<Uint8List>`", a 500 before the file was opened. Found
/// 2026-09-17 by backing up one running CLI server and restoring into
/// another (tool/review_2026-09-17/fix_r1/08_cli_end_to_end.log).
void main() {
  late Directory dir;
  late FhirAntDb source;
  late FhirAntDb target;
  late HttpServer sourceServer;
  late HttpServer targetServer;

  Future<FhirAntDb> store(String name) async {
    final db = FhirAntDb(
      NativeDatabase(
        File('${dir.path}/$name'),
        setup: (raw) => applyStoreCipher(raw, 'the-store-key'),
      ),
    );
    await db.initialize();
    return db;
  }

  Future<HttpServer> serve(FhirAntDb db) => shelf_io.serve(
        (request) => request.url.path == r'$backup'
            ? backupHandler(request, db)
            : restoreHandler(request, db),
        InternetAddress.loopbackIPv4,
        0,
      );

  Uri at(HttpServer server, String path) =>
      Uri.parse('http://127.0.0.1:${server.port}/$path');

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fhirant_restore_socket_');
    source = await store('source.db');
    target = await store('target.db');
    sourceServer = await serve(source);
    targetServer = await serve(target);
  });

  tearDown(() async {
    await sourceServer.close(force: true);
    await targetServer.close(force: true);
    await source.close();
    await target.close();
    await dir.delete(recursive: true);
  });

  test('a backup downloaded from one server restores into another', () async {
    await source.saveResource(
      fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'p1',
        'name': [
          {'family': 'Roundtrip'},
        ],
      }),
    );

    final backup = await http.post(
      at(sourceServer, r'$backup'),
      headers: {'content-type': 'application/fhir+json'},
      body: '{"resourceType":"Parameters","parameter":'
          '[{"name":"passphrase","valueString":"correct horse"}]}',
    );
    expect(backup.statusCode, 200);

    final wrong = await http.post(
      at(targetServer, r'$restore'),
      headers: {
        'content-type': 'application/vnd.sqlite3',
        'x-backup-passphrase': 'wrong horse',
      },
      body: backup.bodyBytes,
    );
    expect(wrong.statusCode, 400, reason: wrong.body);

    final restore = await http.post(
      at(targetServer, r'$restore'),
      headers: {
        'content-type': 'application/vnd.sqlite3',
        'x-backup-passphrase': 'correct horse',
      },
      body: backup.bodyBytes,
    );
    expect(restore.statusCode, 200, reason: restore.body);

    final restored = await target.getResource(
      fhir.R4ResourceType.Patient,
      'p1',
    );
    expect(
      (restored! as fhir.Patient).name!.single.family!.valueString,
      'Roundtrip',
    );
  });

  test('an empty body is a 400, not a 500', () async {
    final response = await http.post(at(targetServer, r'$restore'));
    expect(response.statusCode, 400, reason: response.body);
  });
}
