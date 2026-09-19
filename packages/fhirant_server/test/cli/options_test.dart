import 'package:fhirant_server/src/cli/options.dart';
import 'package:fhirant_server/src/fhirant_server.dart' show kAuditRetention;
import 'package:test/test.dart';

/// REVIEW-2026-09-17 S6: `--config` was declared and never read, and
/// `int.parse(port)` was unguarded (a non-number crashed the binary with a
/// stack trace instead of a usage line).
void main() {
  ServerOptions resolve(List<String> args, {String? config}) =>
      ServerOptions.resolve(
        ServerOptions.parser().parse(args),
        readFile: (path) => config ?? (throw StateError('no file $path')),
      );

  test('defaults', () {
    final o = resolve([]);
    expect(o.port, 8080);
    expect(o.dbPath, 'data/db');
    expect(o.https, isFalse);
    expect(o.devMode, isFalse);
    expect(o.specPath, '/app/fhir_spec');
    expect(o.baseUrl, isNull);
    expect(o.auditRetention, kAuditRetention);
  });

  test('the config file sets what the command line did not', () {
    final o = resolve(
      ['--config', 'server.yaml'],
      config: '''
port: 9090
db-path: /var/lib/fhirant
dev-mode: true
base-url: https://fhir.example.org
audit-retention-days: 30
''',
    );
    expect(o.port, 9090);
    expect(o.dbPath, '/var/lib/fhirant');
    expect(o.devMode, isTrue);
    expect(o.baseUrl, 'https://fhir.example.org');
    expect(o.auditRetention, const Duration(days: 30));
  });

  test('the command line wins over the config file', () {
    final o = resolve(
      ['--config', 'server.yaml', '--port', '7000', '--no-dev-mode'],
      config: 'port: 9090\ndev-mode: true\n',
    );
    expect(o.port, 7000);
    expect(o.devMode, isFalse);
  });

  test('an empty config file configures nothing', () {
    expect(resolve(['--config', 'e.yaml'], config: '').port, 8080);
  });

  test('a config key the CLI does not know is a usage error', () {
    expect(
      () => resolve(['--config', 'c.yaml'], config: 'prot: 1\n'),
      throwsA(
        isA<CliUsageException>().having(
          (e) => e.message,
          'message',
          contains('unknown option "prot"'),
        ),
      ),
    );
  });

  test('a config file that is not a map, or not YAML, is a usage error', () {
    expect(
      () => resolve(['--config', 'c.yaml'], config: '- a\n- b\n'),
      throwsA(isA<CliUsageException>()),
    );
    expect(
      () => resolve(['--config', 'c.yaml'], config: 'port: [unclosed\n'),
      throwsA(isA<CliUsageException>()),
    );
    expect(
      () => resolve(['--config', 'missing.yaml']),
      throwsA(isA<StateError>()),
      reason: 'the reader decides how a missing file surfaces',
    );
  });

  test('a port that is not a number, or out of range, is a usage error', () {
    for (final bad in ['abc', '0', '65536', '-1', '80.5']) {
      expect(
        () => resolve(['--port', bad]),
        throwsA(
          isA<CliUsageException>().having(
            (e) => e.message,
            'message',
            contains('port must be an integer from 1 to 65535'),
          ),
        ),
        reason: bad,
      );
    }
    expect(
      () => resolve(['--config', 'c.yaml'], config: 'port: 70000\n'),
      throwsA(isA<CliUsageException>()),
    );
  });

  test('a retention that is not a positive day count is a usage error', () {
    expect(
      () => resolve(['--audit-retention-days', '0']),
      throwsA(isA<CliUsageException>()),
    );
    expect(
      () => resolve(['--audit-retention-days', 'soon']),
      throwsA(isA<CliUsageException>()),
    );
  });

  group('the encryption key rule is independent of authentication (S4)', () {
    // REVIEW-2026-09-17 S4: --dev-mode both switched authentication off
    // and accepted the public default key.
    test('--dev-mode alone does not allow the public key', () {
      final o = resolve(['--dev-mode']);
      expect(o.devMode, isTrue);
      expect(o.allowPublicKey, isFalse);
      expect(
        encryptionKeyRefusal(
          'default-development-key',
          allowPublicKey: o.allowPublicKey,
        ),
        contains('Refusing to start'),
      );
    });

    test('--allow-public-key alone leaves authentication on', () {
      final o = resolve(['--allow-public-key']);
      expect(o.devMode, isFalse);
      expect(
        encryptionKeyRefusal(
          'default-development-key',
          allowPublicKey: o.allowPublicKey,
        ),
        isNull,
      );
    });

    test('every published key is refused; a real key never is', () {
      for (final k in publicKeys) {
        expect(encryptionKeyRefusal(k, allowPublicKey: false), isNotNull);
      }
      expect(
        encryptionKeyRefusal('a-real-secret', allowPublicKey: false),
        isNull,
      );
    });

    test('the config file can carry it', () {
      final o = resolve(
        ['--config', 'c.yaml'],
        config: 'allow-public-key: true\n',
      );
      expect(o.allowPublicKey, isTrue);
    });
  });
}
