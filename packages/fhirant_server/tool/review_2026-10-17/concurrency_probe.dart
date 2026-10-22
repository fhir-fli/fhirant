// OWASP ASVS 5.0.0 V15.4.2 (L3, read 2026-10-21, verbatim): "Verify that
// checks on a resource's state, such as its existence or permissions, and
// the actions that depend on them are performed as a single atomic
// operation to prevent time-of-check to time-of-use (TOCTOU) race
// conditions."
//
// fhirant runs on one isolate, so a race is two requests interleaving at
// their awaits between a check and the act that depends on it. Each case
// sends a burst of [burst] identical requests at once through the full
// pipeline (createTestServer's handler, in-memory store) and counts what got
// through against what one-at-a-time would allow. One row per case to
// concurrency_probe.tsv, written and flushed as it runs.
//
// Run from packages/fhirant_server:
//   dart run tool/review_2026-10-17/concurrency_probe.dart <burst> <repeats>
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

import '../../test/integration/test_helpers.dart';

late RandomAccessFile _out;

void _row(String name, String rule, int repeat, String observed, bool ok) {
  final line = [
    if (_sequential) 'CONTROL one at a time: $name' else name,
    rule,
    '$repeat',
    observed,
    if (ok) 'PASS' else 'FAIL',
  ].join('\t');
  _out
    ..writeStringSync('$line\n')
    ..flushSync();
  stdout.writeln(line);
}

Future<void> main(List<String> args) async {
  final burst = int.parse(args[0]);
  final repeats = int.parse(args[1]);
  _out = File('tool/review_2026-10-17/concurrency_probe.tsv')
      .openSync(mode: FileMode.write)
    ..writeStringSync('case\tone-at-a-time rule\trepeat\tobserved\tverdict\n')
    ..flushSync();
  for (var i = 0; i < repeats + 1; i++) {
    // Pass 0 is the control, one request at a time.
    _sequential = i == 0;
    await _conditionalCreate(burst, i);
    await _ifMatch(burst, i);
    await _register(burst, i);
    await _refreshReuse(burst, i);
    await _codeReuse(burst, i);
    await _lockout(burst, i);
    await _lastAdmin(i);
  }
  _out.closeSync();
}

Future<({Handler handler, String admin, Future<void> Function() close})>
    _server() async {
  final s = await createTestServer(authMaxRequests: 100000);
  final admin = await issueTestToken(
    s.db,
    username: 'adm',
    role: 'admin',
    scopes: ['system/*.*'],
  );
  return (handler: s.handler, admin: admin, close: s.db.close);
}

/// Whether this pass sends each burst one request at a time: the control,
/// showing what the server allows when nothing interleaves.
bool _sequential = false;

Future<List<Response>> _all(Handler h, List<Request> requests) async {
  if (!_sequential) {
    return Future.wait([for (final r in requests) Future.sync(() => h(r))]);
  }
  return [for (final r in requests) await h(r)];
}

Map<String, String> get _json => {
      'content-type': 'application/fhir+json',
      'accept': 'application/fhir+json',
    };

Future<void> _conditionalCreate(int burst, int i) async {
  final s = await _server();
  final body = jsonEncode({
    'resourceType': 'Patient',
    'identifier': [
      {'system': 'urn:probe', 'value': 'one'},
    ],
  });
  final rs = await _all(s.handler, [
    for (var k = 0; k < burst; k++)
      testRequest(
        'POST',
        '/Patient',
        authToken: s.admin,
        body: body,
        headers: {..._json, 'if-none-exist': 'identifier=urn:probe|one'},
      ),
  ]);
  final created = rs.where((r) => r.statusCode == 201).length;
  final search = await s.handler(
    testRequest(
      'GET',
      '/Patient?identifier=urn:probe|one',
      authToken: s.admin,
      headers: _json,
    ),
  );
  final total = (jsonDecode(await search.readAsString()) as Map)['total'];
  _row(
    'conditional create, $burst at once',
    'http.html: one match, no create',
    i,
    '201s=$created stored=$total '
        'statuses=${rs.map((r) => r.statusCode).toSet()}',
    created == 1 && total == 1,
  );
  await s.close();
}

Future<void> _ifMatch(int burst, int i) async {
  final s = await _server();
  final put = await s.handler(
    testRequest(
      'PUT',
      '/Patient/c1',
      authToken: s.admin,
      body: jsonEncode({'resourceType': 'Patient', 'id': 'c1'}),
      headers: _json,
    ),
  );
  final version = _versionOf(await put.readAsString());
  final rs = await _all(s.handler, [
    for (var k = 0; k < burst; k++)
      testRequest(
        'PUT',
        '/Patient/c1',
        authToken: s.admin,
        body: jsonEncode({
          'resourceType': 'Patient',
          'id': 'c1',
          'gender': k.isEven ? 'male' : 'female',
        }),
        headers: {..._json, 'if-match': 'W/"$version"'},
      ),
  ]);
  final ok = rs.where((r) => r.statusCode == 200).length;
  final read = await s.handler(
    testRequest('GET', '/Patient/c1', authToken: s.admin, headers: _json),
  );
  final after = _versionOf(await read.readAsString());
  _row(
    'If-Match W/"$version" update, $burst at once',
    'http.html 3.1.0.4.1 (version-aware update): one 200, the rest 412',
    i,
    '200s=$ok version after=$after '
        'statuses=${rs.map((r) => r.statusCode).toSet()}',
    ok == 1 && after == '${int.parse(version) + 1}',
  );
  await s.close();
}

String _versionOf(String body) {
  final json = jsonDecode(body) as Map<String, dynamic>;
  return (json['meta'] as Map<String, dynamic>)['versionId'] as String;
}

Future<void> _register(int burst, int i) async {
  final s = await _server();
  final rs = await _all(s.handler, [
    for (var k = 0; k < burst; k++)
      testRequest(
        'POST',
        '/auth/register',
        authToken: s.admin,
        body: jsonEncode({
          'username': 'dup',
          'password': 'a-long-enough-password-123',
        }),
      ),
  ]);
  final created = rs.where((r) => r.statusCode == 201).length;
  _row(
    'register one username, $burst at once',
    'usernames unique: one 201',
    i,
    '201s=$created statuses=${rs.map((r) => r.statusCode).toSet()}',
    created == 1,
  );
  await s.close();
}

Future<Map<String, dynamic>> _login(Handler h, String user, String pw) async {
  final r = await h(
    testRequest(
      'POST',
      '/auth/login',
      body: jsonEncode({'username': user, 'password': pw}),
    ),
  );
  return {
    'status': r.statusCode,
    ...jsonDecode(await r.readAsString()) as Map<String, dynamic>,
  };
}

Future<void> _registerUser(
  ({Handler handler, String admin, Future<void> Function() close}) s,
  String user,
) async {
  final r = await s.handler(
    testRequest(
      'POST',
      '/auth/register',
      authToken: s.admin,
      body: jsonEncode({
        'username': user,
        'password': 'a-long-enough-password-123',
      }),
    ),
  );
  if (r.statusCode != 201) {
    throw StateError('register $user: ${await r.readAsString()}');
  }
}

Future<void> _refreshReuse(int burst, int i) async {
  final s = await _server();
  await _registerUser(s, 'ref');
  final login = await _login(s.handler, 'ref', 'a-long-enough-password-123');
  final token = login['refresh_token'] as String;
  final rs = await _all(s.handler, [
    for (var k = 0; k < burst; k++)
      testRequest(
        'POST',
        '/auth/token',
        body: 'grant_type=refresh_token&refresh_token=$token',
        headers: {'content-type': 'application/x-www-form-urlencoded'},
      ),
  ]);
  final ok = rs.where((r) => r.statusCode == 200).length;
  _row(
    'one refresh token, $burst at once',
    'rotation: a refresh token is used once',
    i,
    '200s=$ok statuses=${rs.map((r) => r.statusCode).toSet()}',
    ok == 1,
  );
  await s.close();
}

Future<void> _codeReuse(int burst, int i) async {
  final s = await createTestServer(authMaxRequests: 100000);
  await issueTestToken(s.db, username: 'code-user', scopes: ['user/*.rs']);
  final userId = (await s.db.getUserByUsername('code-user'))!.id;
  await s.db.createAuthorizationCode(
    code: 'race-code',
    clientId: 'app',
    userId: userId,
    redirectUri: 'http://localhost/cb',
    scope: 'user/*.rs',
    expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  );
  final rs = await _all(s.handler, [
    for (var k = 0; k < burst; k++)
      testRequest(
        'POST',
        '/auth/token',
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'grant_type': 'authorization_code',
          'code': 'race-code',
          'redirect_uri': 'http://localhost/cb',
          'client_id': 'app',
        }),
      ),
  ]);
  final ok = rs.where((r) => r.statusCode == 200).length;
  _row(
    'one authorization code, $burst at once',
    'RFC 6749 4.1.2: used more than once, MUST deny',
    i,
    '200s=$ok statuses=${rs.map((r) => r.statusCode).toSet()}',
    ok == 1,
  );
  await s.db.close();
}

Future<void> _lockout(int burst, int i) async {
  final s = await _server();
  await _registerUser(s, 'lock');
  // Twice the 5 a lock takes, all wrong, at once; then the right password.
  final wrong = await _all(s.handler, [
    for (var k = 0; k < burst; k++)
      testRequest(
        'POST',
        '/auth/login',
        body: jsonEncode({'username': 'lock', 'password': 'wrong-$k'}),
      ),
  ]);
  final right = await _login(s.handler, 'lock', 'a-long-enough-password-123');
  _row(
    '$burst wrong passwords at once, then the right one',
    'lockout after 5 failures: the right password is refused',
    i,
    'wrong statuses=${wrong.map((r) => r.statusCode).toSet()} '
        'then right=${right['status']}',
    right['status'] == 401,
  );
  await s.close();
}

Future<void> _lastAdmin(int i) async {
  final s = await createTestServer(authMaxRequests: 100000);
  final a = await issueTestToken(
    s.db,
    username: 'adm-a',
    role: 'admin',
    scopes: ['system/*.*'],
  );
  final b = await issueTestToken(
    s.db,
    username: 'adm-b',
    role: 'admin',
    scopes: ['system/*.*'],
  );
  final idA = (await s.db.getUserByUsername('adm-a'))!.id;
  final idB = (await s.db.getUserByUsername('adm-b'))!.id;
  final rs = await _all(s.handler, [
    testRequest(
      'PUT',
      '/admin/users/$idB/role',
      authToken: a,
      body: jsonEncode({'role': 'clinician'}),
    ),
    testRequest(
      'PUT',
      '/admin/users/$idA/role',
      authToken: b,
      body: jsonEncode({'role': 'clinician'}),
    ),
  ]);
  final admins = [
    for (final n in ['adm-a', 'adm-b'])
      if ((await s.db.getUserByUsername(n))!.role == 'admin') n,
  ];
  _row(
    'the two admins demote each other at once',
    'the last active admin cannot be demoted (409)',
    i,
    'statuses=${rs.map((r) => r.statusCode).toList()} admins left=$admins',
    admins.isNotEmpty,
  );
  await s.db.close();
}
