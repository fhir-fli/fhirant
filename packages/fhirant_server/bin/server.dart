// bin/server.dart
import 'dart:io';

import 'package:args/args.dart';
import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:fhirant_server/src/utils/jwt_secret.dart';
import 'package:fhirant_server/src/utils/spec_loader.dart';

void main(List<String> arguments) async {
  final logger = FhirantLogging();

  final parser = ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: '8080', help: 'Server port')
    ..addOption('db-path', defaultsTo: 'data/db', help: 'Database file path')
    ..addOption('config', abbr: 'c', help: 'Path to config file (YAML)')
    ..addFlag('https', help: 'Enable HTTPS')
    ..addOption('cert-path', help: 'Path to HTTPS certificate file')
    ..addOption('key-path', help: 'Path to HTTPS private key file')
    ..addFlag(
      'dev-mode',
      help: 'Disable authentication (for testing only)',
    )
    ..addOption(
      'spec-path',
      defaultsTo: '/app/fhir_spec',
      help: 'Path to FHIR spec NDJSON files',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage');

  ArgResults args;
  try {
    args = parser.parse(arguments);
    if (args['help'] as bool) {
      print('FHIR ANT Server\n\nUsage:\n${parser.usage}');
      exit(0);
    }
  } catch (e) {
    logger.logError('Error parsing arguments: $e\n\nUsage:\n${parser.usage}');
    exit(1);
  }

  final port = int.parse(args['port'] as String);
  final dbPath = args['db-path'] as String;
  final encryptionKey = Platform.environment['FHIRANT_ENCRYPTION_KEY'] ??
      'default-development-key';

  // Resolve the JWT signing secret. Preference: FHIRANT_JWT_SECRET (set this
  // for cloud/multi-instance deployments where instances share a secret and
  // the filesystem is ephemeral); otherwise a strong secret is generated once
  // and persisted next to the database so an offline, zero-config deployment
  // gets a stable, unguessable secret without contacting anything.
  final jwtSecretEnv = Platform.environment['FHIRANT_JWT_SECRET'];
  final jwtSecret = JwtSecret.resolveForServer(
    envValue: jwtSecretEnv,
    persistPath: '$dbPath/.jwt_secret',
  );
  if (jwtSecretEnv == null || jwtSecretEnv.isEmpty) {
    logger.logInfo(
      'FHIRANT_JWT_SECRET not set; using a generated secret persisted at '
      '$dbPath/.jwt_secret. Set the env var for multi-instance deployments.',
    );
  }

  if (encryptionKey == 'default-development-key') {
    logger.logWarning(
      'Using default encryption key. Set FHIRANT_ENCRYPTION_KEY for production.',
    );
  }

  // Initialize database
  logger.logInfo('Initializing database at $dbPath');
  final dbDir = Directory(dbPath);
  if (!dbDir.existsSync()) {
    dbDir.createSync(recursive: true);
  }

  final dbFile = File('$dbPath/fhirant.db');
  // SQLite is built from the sqlite3mc source (SQLite3 Multiple Ciphers)
  // via the build hook declared in pubspec.yaml. The cipher/legacy PRAGMAs
  // select the SQLCipher-v4-compatible scheme so databases created by the
  // previous SQLCipher-based builds keep opening.
  final nativeDb = NativeDatabase(
    dbFile,
    setup: (rawDb) {
      rawDb
        ..execute("PRAGMA cipher = 'sqlcipher';")
        ..execute('PRAGMA legacy = 4;')
        ..execute("PRAGMA key = '$encryptionKey';");
      rawDb.config.doubleQuotedStringLiterals = false;
    },
  );
  final db = FhirAntDb(nativeDb);

  try {
    await db.initialize();
    logger.logInfo('Database initialized successfully');
  } catch (e, stackTrace) {
    logger.logError('Failed to initialize database', e, stackTrace);
    exit(1);
  }

  // Load FHIR spec terminology resources on first boot
  try {
    await loadSpecResources(db, args['spec-path'] as String);
  } catch (e, stackTrace) {
    logger.logWarning('Failed to load spec resources: $e');
    logger.logError('Spec loading error', e, stackTrace);
    // Non-fatal — server can still operate without spec resources
  }

  // Create and start server
  final devMode = args['dev-mode'] as bool;
  final server = FhirAntServer(
    db,
    jwtSecret: jwtSecret,
    devMode: devMode,
    maxRequests: devMode ? 1000 : 10,
  );

  if (devMode) {
    logger.logWarning(
      'Dev mode enabled — authentication is disabled. '
      'Do not use in production.',
    );
  }

  try {
    if (args['https'] as bool) {
      final certPath = args['cert-path'] as String?;
      final keyPath = args['key-path'] as String?;

      if (certPath == null ||
          keyPath == null ||
          !File(certPath).existsSync() ||
          !File(keyPath).existsSync()) {
        logger.logError('HTTPS certificate or key not found');
        exit(1);
      }

      final cert = await File(certPath).readAsString();
      final key = await File(keyPath).readAsString();

      await server.startHttps(port, key, cert);
      logger.logInfo('HTTPS server running on port $port');
    } else {
      await server.startHttp(port);
      logger.logInfo('HTTP server running on port $port');
    }

    logger.logInfo('Server running. Press Ctrl+C to stop.');
  } catch (e, stackTrace) {
    logger.logError('Failed to start server', e, stackTrace);
    await db.close();
    exit(1);
  }

  // Handle graceful shutdown
  ProcessSignal.sigint.watch().listen((_) async {
    logger.logInfo('Shutting down server...');
    await server.stop();
    await db.close();
    logger.logInfo('Server stopped successfully');
    exit(0);
  });

  ProcessSignal.sigterm.watch().listen((_) async {
    logger.logInfo('Received SIGTERM, shutting down server...');
    await server.stop();
    await db.close();
    logger.logInfo('Server stopped successfully');
    exit(0);
  });
}
