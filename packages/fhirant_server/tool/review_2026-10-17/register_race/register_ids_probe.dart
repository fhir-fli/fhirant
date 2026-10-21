// Whether /auth/register answers each request with its own account.
// FhirAntDb.createUser ran INSERT, then `SELECT last_insert_rowid()` as a
// second statement, so two registrations interleaving between them could be
// told each other's id. Ten different usernames are registered at once,
// [repeats] times; each answer's `id` and its tokens' `sub`/`userId` are
// compared with the account its username names. One row per repeat to
// register_ids_probe.tsv, flushed as it runs.
//
// Run from packages/fhirant_server:
//   dart run tool/review_2026-10-17/register_race/register_ids_probe.dart <repeats>
import 'dart:convert';
import 'dart:io';

import '../../../test/integration/test_helpers.dart';

Future<void> main(List<String> args) async {
  final repeats = int.parse(args[0]);
  final out =
      File('tool/review_2026-10-17/register_race/register_ids_probe.tsv')
          .openSync(mode: FileMode.write)
        ..writeStringSync('repeat\tanswers\twrong id\twrong token userId\n')
        ..flushSync();
  for (var i = 0; i < repeats; i++) {
    final s = await createTestServer(authMaxRequests: 100000);
    final admin = await issueTestToken(
      s.db,
      username: 'adm',
      role: 'admin',
      scopes: ['system/*.*'],
    );
    final names = [for (var k = 0; k < 10; k++) 'user$k'];
    final rs = await Future.wait([
      for (final n in names)
        Future.sync(
          () => s.handler(
            testRequest(
              'POST',
              '/auth/register',
              authToken: admin,
              body: jsonEncode({
                'username': n,
                'password': 'a-long-enough-password-123',
              }),
            ),
          ),
        ),
    ]);
    var wrongId = 0;
    var wrongToken = 0;
    for (var k = 0; k < names.length; k++) {
      final body =
          jsonDecode(await rs[k].readAsString()) as Map<String, dynamic>;
      final actual = (await s.db.getUserByUsername(names[k]))!.id;
      if (body['id'] != actual) wrongId++;
      final part = (body['token'] as String).split('.')[1];
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(part))),
      ) as Map<String, dynamic>;
      if (claims['userId'] != actual) wrongToken++;
    }
    final row = '$i\t${rs.length}\t$wrongId\t$wrongToken';
    out
      ..writeStringSync('$row\n')
      ..flushSync();
    stdout.writeln(row);
    await s.db.close();
  }
  out.closeSync();
}
