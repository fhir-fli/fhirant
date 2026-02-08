import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:shelf/shelf.dart';

const testJwtSecret = 'test-secret';

/// Creates an authenticated request with required headers for the test pipeline.
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

/// Generates a JWT token for testing.
String generateTestToken({
  int userId = 1,
  String username = 'testuser',
  String role = 'clinician',
}) {
  return JwtService(testJwtSecret).generateToken(
    userId: userId,
    username: username,
    role: role,
  );
}

/// Creates a fresh in-memory DB and full-pipeline handler for integration tests.
Future<({FhirAntDb db, Handler handler})> createTestServer({
  String? exportDir,
}) async {
  final db = FhirAntDb(NativeDatabase.memory());
  await db.initialize();
  final server = FhirAntServer(
    db,
    jwtSecret: testJwtSecret,
    exportDir: exportDir,
  );
  final handler = server.createHandler(server.createRouter());
  return (db: db, handler: handler);
}
