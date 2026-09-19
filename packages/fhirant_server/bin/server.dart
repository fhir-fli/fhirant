// bin/server.dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/auth/bootstrap.dart';
import 'package:fhirant_server/src/cli/options.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:fhirant_server/src/utils/jwt_secret.dart';
import 'package:fhirant_server/src/utils/spec_loader.dart';

void main(List<String> arguments) async {
  final logger = FhirantLogging()
    // Nothing called this, so Logger.root had no listener and EVERY log line
    // this binary writes went nowhere: startup, database initialisation,
    // failures, the lot. The Flutter app calls it (main.dart:46); the
    // standalone server never did, which is why an unknown flag exited 1 in
    // silence. Console only by default — a server run from a terminal has its
    // output collected there, and a file would otherwise appear in the working
    // directory uninvited.
    ..initialize(logFilePath: null);

  final parser = ServerOptions.parser();

  final ServerOptions options;
  try {
    final args = parser.parse(arguments);
    if (args['help'] as bool) {
      // Usage goes to stdout as plain text, not through the JSON logger.
      stdout.writeln('FHIR ANT Server\n\nUsage:\n${parser.usage}');
      exit(0);
    }
    // The command line over the --config file over the defaults; a bad
    // port or an unknown config key is a usage error, not a crash
    // (REVIEW-2026-09-17 S6).
    options = ServerOptions.resolve(args);
  } on FormatException catch (e) {
    // Straight to stderr, not through the logger: a usage error is for the
    // person who typed the command, and it must survive whatever logging is
    // or is not configured.
    stderr.writeln('$e\n\nUsage:\n${parser.usage}');
    exit(1);
  } on CliUsageException catch (e) {
    stderr.writeln('$e\n\nUsage:\n${parser.usage}');
    exit(1);
  }

  final port = options.port;
  final dbPath = options.dbPath;
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

  final devMode = options.devMode;

  // The key rule stands on its own: --dev-mode turns authentication off
  // and nothing else; opening a store under a public key takes
  // --allow-public-key (REVIEW-2026-09-17 S4).
  final keyRefusal = encryptionKeyRefusal(
    encryptionKey,
    allowPublicKey: options.allowPublicKey,
  );
  if (keyRefusal != null) {
    logger.logError(keyRefusal);
    exit(1);
  }
  if (publicKeys.contains(encryptionKey)) {
    logger.logWarning(
      'Using the publicly known default encryption key (--allow-public-key). '
      'Set FHIRANT_ENCRYPTION_KEY for any real deployment.',
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
    setup: (rawDb) => applyStoreCipher(rawDb, encryptionKey),
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
    await loadSpecResources(db, options.specPath);
  } catch (e, stackTrace) {
    logger
      ..logWarning('Failed to load spec resources: $e')
      ..logError('Spec loading error', e, stackTrace);
    // Non-fatal — server can still operate without spec resources
  }

  // The first administrator (REVIEW-2026-09-17 A15; auth/bootstrap.dart):
  // seeded from FHIRANT_ADMIN_USERNAME / FHIRANT_ADMIN_PASSWORD when set,
  // otherwise the first registration must carry a one-time token issued
  // here, logged, and written owner-only beside the database. In dev mode
  // registration is refused anyway (accounts are the operator's), so
  // neither applies.
  String? bootstrapToken;
  if (!devMode) {
    switch (await seedAdminFromEnvironment(db, Platform.environment)) {
      case SeedCreated(username: final u):
        logger.logInfo('Administrator "$u" created from the environment');
      case SeedAlreadyProvisioned():
        logger.logInfo(
          'FHIRANT_ADMIN_USERNAME set but an administrator exists; ignored',
        );
      case SeedRefused(message: final m):
        logger.logError('Refusing to start: $m');
        await db.close();
        exit(1);
      case SeedNotConfigured():
        break;
    }
    bootstrapToken = await issueBootstrapToken(
      db,
      persistPath: '$dbPath/.bootstrap_token',
    );
    if (bootstrapToken != null) {
      logger.logWarning(
        'No accounts yet. The first POST /auth/register creates the '
        'administrator and must carry this one-time token in the '
        'X-Bootstrap-Token header (or the bootstrap_token body field):\n'
        '$bootstrapToken\n'
        'It is also in $dbPath/.bootstrap_token (owner-readable). To seed '
        'the administrator without it, set FHIRANT_ADMIN_USERNAME and '
        'FHIRANT_ADMIN_PASSWORD and restart.',
      );
    }
  }

  // Create and start server
  final server = FhirAntServer(
    db,
    jwtSecret: jwtSecret,
    devMode: devMode,
    maxRequests: devMode ? 1000 : 600,
    baseUrl: options.baseUrl,
    bootstrapToken: bootstrapToken,
    auditRetention: options.auditRetention,
  );

  if (devMode) {
    logger.logWarning(
      'Dev mode enabled — authentication is disabled. '
      'Do not use in production.',
    );
  }

  try {
    if (options.https) {
      final certPath = options.certPath;
      final keyPath = options.keyPath;

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
