import 'dart:convert';
import 'dart:io';

import 'package:fhirant_server/src/utils/jwt_secret.dart';
import 'package:test/test.dart';

void main() {
  group('JwtSecret.generate', () {
    test('produces decodable 32-byte base64url secrets', () {
      final secret = JwtSecret.generate();
      final bytes = base64Url.decode(secret);
      expect(bytes.length, 32);
    });

    test('is unique across calls (cryptographic randomness)', () {
      final secrets = List.generate(100, (_) => JwtSecret.generate()).toSet();
      expect(secrets.length, 100);
    });

    test('never returns the old hardcoded default', () {
      const oldDefault = 'fhirant-dev-secret-change-in-production';
      for (var i = 0; i < 50; i++) {
        expect(JwtSecret.generate(), isNot(oldDefault));
      }
    });
  });

  group('JwtSecret.resolveForServer', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('jwt_secret_test_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('explicit value wins over everything', () {
      final result = JwtSecret.resolveForServer(
        explicit: 'explicit-secret',
        envValue: 'env-secret',
        persistPath: '${tmp.path}/.jwt_secret',
      );
      expect(result, 'explicit-secret');
      // Persist file must not be created when an explicit value is supplied.
      expect(File('${tmp.path}/.jwt_secret').existsSync(), isFalse);
    });

    test('env value wins over persistence', () {
      final result = JwtSecret.resolveForServer(
        envValue: 'env-secret',
        persistPath: '${tmp.path}/.jwt_secret',
      );
      expect(result, 'env-secret');
      expect(File('${tmp.path}/.jwt_secret').existsSync(), isFalse);
    });

    test('empty explicit/env are ignored, falling through to persistence', () {
      final result = JwtSecret.resolveForServer(
        explicit: '',
        envValue: '',
        persistPath: '${tmp.path}/.jwt_secret',
      );
      expect(result, isNotEmpty);
      expect(File('${tmp.path}/.jwt_secret').existsSync(), isTrue);
    });

    test('generates and persists a strong secret when none is configured', () {
      final path = '${tmp.path}/sub/.jwt_secret';
      final result = JwtSecret.resolveForServer(persistPath: path);

      // Strong: decodes to 32 bytes, is not the old default.
      expect(base64Url.decode(result).length, 32);
      expect(result, isNot('fhirant-dev-secret-change-in-production'));

      // Persisted (parent dir created) with the exact value.
      final file = File(path);
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync().trim(), result);
    });

    test('reuses an already-persisted secret (stable across restarts)', () {
      final path = '${tmp.path}/.jwt_secret';
      final first = JwtSecret.resolveForServer(persistPath: path);
      final second = JwtSecret.resolveForServer(persistPath: path);
      expect(second, first);
    });

    test('regenerates when the persisted file is empty', () {
      final path = '${tmp.path}/.jwt_secret';
      File(path).writeAsStringSync('   ');
      final result = JwtSecret.resolveForServer(persistPath: path);
      expect(result.trim(), isNotEmpty);
      expect(File(path).readAsStringSync().trim(), result);
    });

    test('persisted secret is owner-only on POSIX platforms', () {
      if (!Platform.isLinux && !Platform.isMacOS) return;
      final path = '${tmp.path}/.jwt_secret';
      JwtSecret.resolveForServer(persistPath: path);
      final mode = File(path).statSync().mode & 0x1FF; // low 9 permission bits
      expect(mode, 0x180, // 0o600
          reason: 'expected rw------- (0600), got ${mode.toRadixString(8)}');
    });
  });
}
