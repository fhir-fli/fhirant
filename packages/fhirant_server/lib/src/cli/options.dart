import 'dart:io';

import 'package:args/args.dart';
import 'package:fhirant_server/src/fhirant_server.dart' show kAuditRetention;
import 'package:yaml/yaml.dart';

/// A usage error: what the person who typed the command needs to read.
/// bin/server.dart prints it with the usage and exits 1.
class CliUsageException implements Exception {
  const CliUsageException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The CLI's settings, from the command line and an optional YAML config
/// file (REVIEW-2026-09-17 S6: `--config` was declared and never read, and
/// `int.parse(port)` was unguarded).
///
/// The config file is a map whose keys are the long option names
/// (`port`, `db-path`, `https`, `cert-path`, `key-path`, `spec-path`,
/// `base-url`, `audit-retention-days`, `dev-mode`). A value given on the
/// command line wins over the file; the file wins over the default. A key
/// the CLI does not know is a usage error, so a misspelling is not
/// silently ignored.
class ServerOptions {
  const ServerOptions({
    required this.port,
    required this.dbPath,
    required this.https,
    required this.certPath,
    required this.keyPath,
    required this.devMode,
    required this.specPath,
    required this.baseUrl,
    required this.auditRetention,
    this.allowPublicKey = false,
  });

  final int port;
  final String dbPath;
  final bool https;
  final String? certPath;
  final String? keyPath;
  final bool devMode;
  final String specPath;
  final String? baseUrl;
  final Duration auditRetention;

  /// Whether a store may be opened under a key this repository publishes
  /// ([publicKeys]). Its own switch, independent of [devMode]
  /// (REVIEW-2026-09-17 S4: `--dev-mode` both turned authentication off and
  /// accepted the public key, so either choice forced the other).
  final bool allowPublicKey;

  /// The parser, shared by the binary (for `--help`) and [resolve].
  static ArgParser parser() => ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: '8080', help: 'Server port')
    ..addOption('db-path', defaultsTo: 'data/db', help: 'Database file path')
    ..addOption(
      'config',
      abbr: 'c',
      help: 'Path to a YAML config file whose keys are these option names; '
          'the command line overrides it',
    )
    ..addFlag('https', help: 'Enable HTTPS')
    ..addOption('cert-path', help: 'Path to HTTPS certificate file')
    ..addOption('key-path', help: 'Path to HTTPS private key file')
    ..addFlag(
      'dev-mode',
      help: 'Disable authentication (for testing only). Does not change the '
          'encryption key rule; see --allow-public-key.',
    )
    ..addFlag(
      'allow-public-key',
      help: 'Open the store under the publicly known default key when '
          'FHIRANT_ENCRYPTION_KEY is unset (throwaway databases only)',
    )
    ..addOption(
      'spec-path',
      defaultsTo: '/app/fhir_spec',
      help: 'Path to FHIR spec NDJSON files',
    )
    ..addOption(
      'base-url',
      help: 'The URL clients reach this server by (e.g. https://host:8080). '
          'Lets a search tell an absolute reference to this server from one '
          'to another server (R4B search 3.1.1.4.12). Optional.',
    )
    ..addOption(
      'audit-retention-days',
      defaultsTo: '${kAuditRetention.inDays}',
      help: 'How many days AuditEvents are kept before the hourly sweep '
          'removes them (default six years, 45 CFR 164.316(b)(2)(i)).',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage');

  /// The option names a config file may carry: every option but `config`
  /// and `help`.
  static const Set<String> configKeys = {
    'port',
    'db-path',
    'https',
    'cert-path',
    'key-path',
    'dev-mode',
    'allow-public-key',
    'spec-path',
    'base-url',
    'audit-retention-days',
  };

  /// Resolves [arguments] (already parsed as [args]) over the config file
  /// they name, if any. [readFile] reads the config file; tests pass their
  /// own.
  // One entry point shared by the binary and the tests; a factory
  // would read no better.
  // ignore: prefer_constructors_over_static_methods
  static ServerOptions resolve(
    ArgResults args, {
    String Function(String path) readFile = _readFile,
  }) {
    final fromFile = <String, Object?>{};
    final configPath = args['config'] as String?;
    if (configPath != null) {
      final Object? doc;
      try {
        doc = loadYaml(readFile(configPath));
      } on FileSystemException catch (e) {
        throw CliUsageException('Cannot read config file $configPath: $e');
      } on YamlException catch (e) {
        throw CliUsageException('Config file $configPath is not YAML: $e');
      }
      if (doc == null) {
        // An empty file configures nothing.
      } else if (doc is! YamlMap) {
        throw CliUsageException(
          'Config file $configPath must be a map of option names to values',
        );
      } else {
        for (final entry in doc.entries) {
          final key = entry.key.toString();
          if (!configKeys.contains(key)) {
            throw CliUsageException(
              'Config file $configPath: unknown option "$key" (known: '
              '${configKeys.join(', ')})',
            );
          }
          fromFile[key] = entry.value;
        }
      }
    }

    // The command line wins where it was given; the file next; the
    // parser's default last.
    Object? pick(String name) =>
        args.wasParsed(name) ? args[name] : (fromFile[name] ?? args[name]);

    String? optionalString(String name) {
      final v = pick(name);
      if (v == null) return null;
      if (v is String) return v.isEmpty ? null : v;
      throw CliUsageException('$name must be a string, got "$v"');
    }

    String requiredString(String name) => optionalString(name)!;

    bool flag(String name) {
      final v = pick(name);
      if (v is bool) return v;
      if (v is String && (v == 'true' || v == 'false')) return v == 'true';
      throw CliUsageException('$name must be true or false, got "$v"');
    }

    int integer(String name, {required int min, required int max}) {
      final v = pick(name);
      final n = v is int ? v : int.tryParse(v.toString());
      if (n == null || n < min || n > max) {
        throw CliUsageException(
          '$name must be an integer from $min to $max, got "$v"',
        );
      }
      return n;
    }

    return ServerOptions(
      port: integer('port', min: 1, max: 65535),
      dbPath: requiredString('db-path'),
      https: flag('https'),
      certPath: optionalString('cert-path'),
      keyPath: optionalString('key-path'),
      devMode: flag('dev-mode'),
      allowPublicKey: flag('allow-public-key'),
      specPath: requiredString('spec-path'),
      baseUrl: optionalString('base-url'),
      auditRetention: Duration(
        days: integer('audit-retention-days', min: 1, max: 36500),
      ),
    );
  }

  static String _readFile(String path) => File(path).readAsStringSync();
}

/// Keys that are public because they are written in this repository: the
/// in-code fallback in bin/server.dart and the placeholder
/// docker-compose.yml once carried. A database encrypted under either is
/// encrypted under nothing.
const Set<String> publicKeys = {
  'default-development-key',
  'change-me-in-production',
};

/// Why the server must not open a store under [encryptionKey], or null.
/// Decided by [allowPublicKey] alone, never by whether authentication is
/// on (REVIEW-2026-09-17 S4).
String? encryptionKeyRefusal(
  String encryptionKey, {
  required bool allowPublicKey,
}) {
  if (!publicKeys.contains(encryptionKey) || allowPublicKey) return null;
  return 'Refusing to start: FHIRANT_ENCRYPTION_KEY is not set (or is a '
      'key published in this repository), so the database would be '
      'encrypted under a publicly known key. Set FHIRANT_ENCRYPTION_KEY, or '
      'pass --allow-public-key for a throwaway database.';
}
