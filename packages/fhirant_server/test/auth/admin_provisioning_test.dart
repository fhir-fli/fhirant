import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/auth/admin_provisioning.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';
import 'package:test/test.dart';

void main() {
  late FhirAntDb db;

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
  });

  tearDown(() async {
    await db.close();
  });

  group('AdminProvisioning.createInitialAdmin', () {
    const goodPassword = 'correct horse battery';

    test('creates the first admin on an empty database', () async {
      final result = await AdminProvisioning.createInitialAdmin(
        db,
        'operator',
        goodPassword,
      );

      expect(result.ok, isTrue);
      expect(result.status, AdminSetupStatus.created);
      expect(result.userId, isNotNull);

      final user = await db.getUserByUsername('operator');
      expect(user, isNotNull);
      expect(user!.role, 'admin');
      // Default admin scopes are system-level (grants the privileged ops).
      expect(
        (jsonDecode(user.scopes!) as List).cast<String>(),
        contains('system/*.*'),
      );
    });

    test('stores a salted hash, never the plaintext password', () async {
      await AdminProvisioning.createInitialAdmin(db, 'operator', goodPassword);
      final user = await db.getUserByUsername('operator');

      expect(user!.passwordHash, isNot(contains(goodPassword)));
      expect(user.salt, isNotEmpty);
      // The stored hash verifies against the original password.
      expect(
        PasswordHasher.verifyPassword(
          goodPassword,
          user.salt,
          user.passwordHash,
        ),
        isTrue,
      );
    });

    test('refuses when a user already exists (bootstrap is one-time)',
        () async {
      final first = await AdminProvisioning.createInitialAdmin(
        db,
        'operator',
        goodPassword,
      );
      expect(first.ok, isTrue);

      final second = await AdminProvisioning.createInitialAdmin(
        db,
        'intruder',
        goodPassword,
      );
      expect(second.status, AdminSetupStatus.alreadyExists);
      expect(second.ok, isFalse);
      // No second account was created.
      expect(await db.getUserCount(), 1);
      expect(await db.getUserByUsername('intruder'), isNull);
    });

    test('rejects a too-short username without creating anything', () async {
      final result = await AdminProvisioning.createInitialAdmin(
        db,
        'ab',
        goodPassword,
      );
      expect(result.status, AdminSetupStatus.invalid);
      expect(result.message, contains('3'));
      expect(await db.getUserCount(), 0);
    });

    test('rejects a password that fails policy (too short)', () async {
      final result =
          await AdminProvisioning.createInitialAdmin(db, 'operator', 'short');
      expect(result.status, AdminSetupStatus.invalid);
      expect(result.message, isNotNull);
      expect(await db.getUserCount(), 0);
    });

    test('trims surrounding whitespace from the username', () async {
      final result = await AdminProvisioning.createInitialAdmin(
        db,
        '  operator  ',
        goodPassword,
      );
      expect(result.ok, isTrue);
      expect(await db.getUserByUsername('operator'), isNotNull);
    });
  });
}
