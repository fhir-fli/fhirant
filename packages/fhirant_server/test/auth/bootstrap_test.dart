// Real Argon2id hashes when an administrator is seeded.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/fhirant_server.dart';
import 'package:test/test.dart';

/// REVIEW-2026-09-17 A15: the first administrator of a headless server
/// comes from the environment or from a one-time token issued at start;
/// see `auth/bootstrap.dart` for the two patterns followed.
void main() {
  late FhirAntDb db;
  late Directory dir;

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
    dir = await Directory.systemTemp.createTemp('bootstrap');
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  group('seedAdminFromEnvironment', () {
    test('does nothing when neither variable is set', () async {
      expect(await seedAdminFromEnvironment(db, {}), isA<SeedNotConfigured>());
      expect(await db.getUserCount(), 0);
    });

    test('creates the administrator when both are set', () async {
      final outcome = await seedAdminFromEnvironment(db, {
        adminUsernameEnv: 'ops-admin',
        adminPasswordEnv: 'Seeded-Password-1',
      });
      expect(outcome, isA<SeedCreated>());
      final user = (await db.getUserByUsername('ops-admin'))!;
      expect(user.role, 'admin');
      expect(user.active, isTrue);
      expect(
        await PasswordHasher.verifyPassword(
          'Seeded-Password-1',
          user.salt,
          user.passwordHash,
        ),
        isTrue,
      );
    });

    test('refuses one variable without the other', () async {
      expect(
        await seedAdminFromEnvironment(db, {adminUsernameEnv: 'ops-admin'}),
        isA<SeedRefused>(),
      );
      expect(
        await seedAdminFromEnvironment(db, {adminPasswordEnv: 'Seeded-1x'}),
        isA<SeedRefused>(),
      );
      expect(await db.getUserCount(), 0);
    });

    test('refuses a password outside the policy', () async {
      final outcome = await seedAdminFromEnvironment(db, {
        adminUsernameEnv: 'ops-admin',
        adminPasswordEnv: 'short',
      });
      expect(outcome, isA<SeedRefused>());
      expect(await db.getUserCount(), 0);
    });

    test('is a bootstrap, not a reset: an existing administrator stands',
        () async {
      await seedAdminFromEnvironment(db, {
        adminUsernameEnv: 'ops-admin',
        adminPasswordEnv: 'Seeded-Password-1',
      });
      final again = await seedAdminFromEnvironment(db, {
        adminUsernameEnv: 'someone-else',
        adminPasswordEnv: 'Another-Password-1',
      });
      expect(again, isA<SeedAlreadyProvisioned>());
      expect(await db.getUserByUsername('someone-else'), isNull);
    });
  });

  group('issueBootstrapToken', () {
    test(
        'issues a fresh token and writes it beside the database, while '
        'the store has no account', () async {
      final path = '${dir.path}/.bootstrap_token';
      final first = await issueBootstrapToken(db, persistPath: path);
      expect(first, isNotNull);
      expect(first!.length, greaterThanOrEqualTo(40));
      expect(File(path).readAsStringSync(), first);
      if (Platform.isLinux || Platform.isMacOS) {
        final mode = File(path).statSync().modeString();
        expect(mode, 'rw-------');
      }
      final second = await issueBootstrapToken(db, persistPath: path);
      expect(second, isNot(first), reason: 'never read back from the file');
      expect(File(path).readAsStringSync(), second);
    });

    test('issues nothing once an account exists, and removes the file',
        () async {
      final path = '${dir.path}/.bootstrap_token';
      await issueBootstrapToken(db, persistPath: path);
      await seedAdminFromEnvironment(db, {
        adminUsernameEnv: 'ops-admin',
        adminPasswordEnv: 'Seeded-Password-1',
      });
      expect(await issueBootstrapToken(db, persistPath: path), isNull);
      expect(File(path).existsSync(), isFalse);
    });
  });

  test('bootstrapTokenMatches compares whole tokens', () {
    final t = generateBootstrapToken();
    expect(bootstrapTokenMatches(t, t), isTrue);
    expect(bootstrapTokenMatches(t.substring(1), t), isFalse);
    expect(bootstrapTokenMatches('${t}x', t), isFalse);
    expect(bootstrapTokenMatches(generateBootstrapToken(), t), isFalse);
  });
}
