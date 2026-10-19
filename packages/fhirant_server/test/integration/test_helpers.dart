import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
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
/// The auth middleware re-reads the account behind a token on every request
/// (REVIEW-2026-09-08 row 14: a deactivated or locked account's live tokens
/// used to keep working), so a token whose user id has no row is refused.
/// This creates the account on first use, reuses it by [username] after,
/// and mints its token; the row carries the role and scopes for the record,
/// the token's claims are what the middleware enforces.
Future<String> issueTestToken(
  FhirAntDb db, {
  String username = 'testuser',
  String role = 'clinician',
  List<String>? scopes,
  String? patientId,
}) async {
  final existing = await db.getUserByUsername(username);
  final userId = existing?.id ??
      await db.createUser(
        username: username,
        passwordHash: 'not-a-hash',
        salt: 'not-a-salt',
        role: role,
        scopes: scopes == null ? null : jsonEncode(scopes),
        patientId: patientId,
      );
  return JwtService(testJwtSecret).generateToken(
    userId: userId,
    username: username,
    role: role,
    scopes: scopes,
    patientId: patientId,
  );
}

/// Generates a JWT token for testing, for a request that does NOT reach the
/// auth middleware (a handler called directly); see [issueTestToken] for
/// requests through the pipeline.
String generateTestToken({
  int userId = 1,
  String username = 'testuser',
  String role = 'clinician',
  List<String>? scopes,
  String? patientId,
}) {
  return JwtService(testJwtSecret).generateToken(
    userId: userId,
    username: username,
    role: role,
    scopes: scopes,
    patientId: patientId,
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
Future<({FhirAntDb db, Handler handler})> createTestServer({
  String? exportDir,
  bool devMode = false,
  String? bootstrapToken,
  int maxRequests = 600,
  int authMaxRequests = 10,
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
  );
  final handler = server.createHandler(server.createRouter());
  return (db: db, handler: handler);
}
