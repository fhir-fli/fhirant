import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:fhirant_server/src/services/disk_space.dart';
import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:shelf/shelf.dart';

const testJwtSecret = 'test-secret';

/// Creates an authenticated request with required headers for the test
/// pipeline.
///
/// The X-Forwarded-For header is required because shelf_rate_limiter's
/// key generator crashes when shelf.io.connection_info is absent (as in tests).
Request testRequest(
  String method,
  String path, {
  String? body,
  Map<String, String>? headers,
  String? authToken,
}) {
  final allHeaders = <String, String>{
    'x-forwarded-for': '127.0.0.1',
    ...?headers,
  };
  if (authToken != null) {
    allHeaders['authorization'] = 'Bearer $authToken';
  }

  return Request(
    method,
    Uri.parse('http://localhost:8080$path'),
    body: body,
    headers: allHeaders,
  );
}

/// Polls export job [jobId]'s status until it is no longer 202 and returns
/// that response, or throws after [timeout].
///
/// The export runs in the background, so how long it takes depends on the
/// machine's load. A fixed 100 polls 50 ms apart (5 s) ran out in a full
/// suite run (measured 2026-10-18: export_binary_test saw only 202s in 1 of
/// 6 runs); the export tests that already polled to a deadline used 20 s.
Future<Response> pollExport(
  Handler handler,
  String jobId, {
  String? authToken,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final r = await handler(
      testRequest('GET', '/\$export-poll-status/$jobId', authToken: authToken),
    );
    if (r.statusCode != 202) return r;
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Export $jobId still answered 202 after $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// A token for an account that EXISTS in [db].
///
/// The auth middleware finds the account a token names by its key
/// (`sub`, `User.accountKey`) and reads the role, scopes and patient
/// context from it, so a token for no row is refused. This creates the
/// account on first use with [role], [scopes] and [patientId], reuses it by
/// [username] after, and mints its token. On reuse the account's role
/// stands: the token carries none. The token's scope is [scopes], which the
/// middleware narrows to what the account holds. [issuer] is the server's
/// `baseUrl` when it was built with one: its tokens' `iss` and `aud`.
Future<String> issueTestToken(
  FhirAntDb db, {
  String username = 'testuser',
  String role = 'clinician',
  List<String>? scopes,
  String? patientId,
  String? issuer,
}) async {
  final existing = await db.getUserByUsername(username);
  final user = existing ??
      (await db.getUserById(
        await db.createUser(
          username: username,
          passwordHash: 'not-a-hash',
          salt: 'not-a-salt',
          role: role,
          scopes: scopes == null ? null : jsonEncode(scopes),
          patientId: patientId,
        ),
      ))!;
  return JwtService(testJwtSecret, issuer: issuer).generateToken(
    subject: user.accountKey,
    scopes: scopes,
    generation: user.tokenGeneration,
  );
}

/// A signed access token naming the account key [subject], for a request
/// that does NOT need the account to exist (a refusal is what is tested);
/// see [issueTestToken] for requests through the pipeline.
String generateTestToken({
  String subject = 'no-such-account',
  List<String>? scopes,
}) {
  return JwtService(testJwtSecret).generateToken(
    subject: subject,
    scopes: scopes,
  );
}

/// An account for a test to ACT ON, distinct from any account it
/// authenticates with. Returns its id.
///
/// A test that aims an admin route at the account it is signed in as can
/// deactivate or demote itself mid-run, after which every request is
/// refused and the test measures the refusal instead of the route. That
/// happened: `every_route_is_audited_test.dart` mapped `<userId>` to 1,
/// its own admin, and 60 routes looked unaudited.
Future<int> createTargetUser(
  FhirAntDb db, {
  String username = 'target-user',
}) async {
  await issueTestToken(db, username: username, scopes: ['user/*.rs']);
  return (await db.getUserByUsername(username))!.id;
}

/// Creates a fresh in-memory DB and full-pipeline handler for integration
/// tests.
Future<({FhirAntDb db, Handler handler, FhirAntServer server})>
    createTestServer({
  String? exportDir,
  bool devMode = false,
  String? bootstrapToken,
  int maxRequests = 600,
  int authMaxRequests = 10,
  DiskSpace? diskSpace,
  String? baseUrl,
}) async {
  final db = FhirAntDb(NativeDatabase.memory());
  await db.initialize();
  final server = FhirAntServer(
    db,
    jwtSecret: testJwtSecret,
    exportDir: exportDir,
    devMode: devMode,
    bootstrapToken: bootstrapToken,
    maxRequests: maxRequests,
    authMaxRequests: authMaxRequests,
    diskSpace: diskSpace,
    baseUrl: baseUrl,
  );
  final handler = server.createHandler(server.createRouter());
  return (db: db, handler: handler, server: server);
}

/// Registers an account as the administrator holding [adminToken], then
/// goes through what its owner and the administrator do before the first
/// sign-in (`auth/owner_claim.dart`): the owner sends [password] to
/// `/auth/claim`, the administrator approves it with the code, the owner
/// signs in. [fields] is the registration body (username, role, scopes,
/// patient), without a password. Returns the registration reply with the
/// session the sign-in opened (`token`, `refresh_token`).
Future<Map<String, dynamic>> registerByAdmin(
  Handler handler,
  String adminToken,
  Map<String, dynamic> fields, {
  required String password,
}) async {
  Future<(int, Map<String, dynamic>)> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final r = await handler(
      testRequest(
        'POST',
        path,
        authToken: token,
        headers: {'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
    return (
      r.statusCode,
      jsonDecode(await r.readAsString()) as Map<String, dynamic>,
    );
  }

  final (registered, reply) =
      await post('/auth/register', fields, token: adminToken);
  if (registered != 201) {
    throw StateError('registration: $registered $reply');
  }
  final (claimed, claim) = await post('/auth/claim', {
    'username': fields['username'],
    'new_password': password,
  });
  if (claimed != 202) throw StateError('claim: $claimed $claim');
  final (approved, approval) = await post(
    '/admin/users/${reply['id']}/approve',
    {'code': claim['code']},
    token: adminToken,
  );
  if (approved != 200) throw StateError('approval: $approved $approval');
  final (signedIn, session) = await post('/auth/login', {
    'username': fields['username'],
    'password': password,
  });
  if (signedIn != 200) throw StateError('login: $signedIn $session');
  return {...reply, ...session};
}
