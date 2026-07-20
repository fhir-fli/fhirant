import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/login_handler.dart';
import 'package:fhirant_server/src/utils/jwt_service.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// A successful login must transparently upgrade an outdated password hash to
/// the current KDF, so existing accounts get the stronger hashing with no user
/// action and the legacy format disappears over time.
void main() {
  late FhirAntDb db;
  final jwt = JwtService('test-secret');

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
  });

  tearDown(() async {
    await db.close();
  });

  // Exactly how the old PasswordHasher stored a hash.
  String legacyHash(String password, String salt) =>
      Hmac(sha256, utf8.encode(salt)).convert(utf8.encode(password)).toString();

  Request loginRequest(String username, String password) => Request(
        'POST',
        Uri.parse('http://localhost:8080/auth/login'),
        body: jsonEncode({'username': username, 'password': password}),
      );

  test('a legacy-hashed account is rehashed to PBKDF2 on successful login',
      () async {
    const username = 'operator';
    const password = 'OldButValidPassword1';
    const salt = 'legacy-salt-value';

    await db.createUser(
      username: username,
      passwordHash: legacyHash(password, salt),
      salt: salt,
      role: 'admin',
    );

    // Sanity: stored as legacy, flagged for rehash.
    final before = await db.getUserByUsername(username);
    expect(PasswordHasher.needsRehash(before!.passwordHash), isTrue);

    final response =
        await loginHandler(loginRequest(username, password), db, jwt);
    expect(response.statusCode, 200);

    // The stored hash is now the current PBKDF2 format and no longer flagged.
    final after = await db.getUserByUsername(username);
    expect(after!.passwordHash, startsWith(r'pbkdf2$'));
    expect(PasswordHasher.needsRehash(after.passwordHash), isFalse);

    // And the upgraded hash still verifies the same password.
    expect(
      PasswordHasher.verifyPassword(password, after.salt, after.passwordHash),
      isTrue,
    );
  });

  test('a current PBKDF2 hash is left unchanged on login', () async {
    const username = 'operator';
    const password = 'AlreadyStrongPassword1';
    final salt = PasswordHasher.generateSalt();

    await db.createUser(
      username: username,
      passwordHash: PasswordHasher.hashPassword(password, salt),
      salt: salt,
      role: 'admin',
    );
    final before = await db.getUserByUsername(username);

    final response =
        await loginHandler(loginRequest(username, password), db, jwt);
    expect(response.statusCode, 200);

    final after = await db.getUserByUsername(username);
    // Unchanged (same salt + hash) — no needless rewrite.
    expect(after!.salt, before!.salt);
    expect(after.passwordHash, before.passwordHash);
  });
}
