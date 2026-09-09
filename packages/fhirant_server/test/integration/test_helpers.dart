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

/// Creates a fresh in-memory DB and full-pipeline handler for integration
/// tests.
Future<({FhirAntDb db, Handler handler})> createTestServer({
  String? exportDir,
  bool devMode = false,
}) async {
  final db = FhirAntDb(NativeDatabase.memory());
  await db.initialize();
  final server = FhirAntServer(
    db,
    jwtSecret: testJwtSecret,
    exportDir: exportDir,
    devMode: devMode,
  );
  final handler = server.createHandler(server.createRouter());
  return (db: db, handler: handler);
}
