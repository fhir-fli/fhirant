// bin/server.dart
import 'dart:ffi';
import 'dart:io';
import 'package:args/args.dart';
import 'package:sqlite3/open.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/utils/sqlcipher_loader.dart';

void main(List<String> arguments) async {
  final logger = FhirantLogging();

  final parser = ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: '8080', help: 'Server port')
    ..addOption('db-path', defaultsTo: 'data/db', help: 'Database file path')
    ..addOption('sqlcipher-path', help: 'Path to SQLCipher library')
    ..addOption('config', abbr: 'c', help: 'Path to config file (YAML)')
    ..addFlag('https', defaultsTo: false, help: 'Enable HTTPS')
    ..addOption('cert-path', help: 'Path to HTTPS certificate file')
    ..addOption('key-path', help: 'Path to HTTPS private key file')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage');

  ArgResults args;
  try {
    args = parser.parse(arguments);
    if (args['help']) {
      print('FHIR ANT Server\n\nUsage:\n${parser.usage}');
      exit(0);
    }
  } catch (e) {
    logger.logError('Error parsing arguments: $e\n\nUsage:\n${parser.usage}');
    exit(1);
  }

  final port = int.parse(args['port']);
  final dbPath = args['db-path'];
  final encryptionKey = Platform.environment['FHIRANT_ENCRYPTION_KEY'] ??
      'default-development-key';

  if (encryptionKey == 'default-development-key') {
    logger.logWarning(
      'Using default encryption key. Set FHIRANT_ENCRYPTION_KEY for production.',
    );
  }

  // Load SQLCipher with SqlCipherLoader
  try {
    SqlCipherLoader.load(customPath: args['sqlcipher-path']);
    logger.logInfo('SQLCipher loaded successfully');
  } catch (e, stackTrace) {
    logger.logError('Failed to load SQLCipher', e, stackTrace);
    exit(1);
  }

  // Initialize database
  // Note: FhirAntDb() constructor takes no parameters
  // Database path and encryption are handled internally
  logger.logInfo('Initializing database at $dbPath');
  final db = FhirAntDb();

  try {
    await db.initialize();
    logger.logInfo('Database initialized successfully');
  } catch (e, stackTrace) {
    logger.logError('Failed to initialize database', e, stackTrace);
    exit(1);
  }

  // Create and start server
  final server = FhirAntServer(db);

  try {
    if (args['https']) {
      final certPath = args['cert-path'];
      final keyPath = args['key-path'];

      if (!File(certPath).existsSync() || !File(keyPath).existsSync()) {
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

// Keep existing SQLCipher setup function
Future<void> setupSqlCipherWithPath(String libraryPath) async {
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open(libraryPath),
    );
  } else if (Platform.isMacOS) {
    open.overrideFor(
      OperatingSystem.macOS,
      () => DynamicLibrary.open(libraryPath),
    );
  } else if (Platform.isWindows) {
    open.overrideFor(
      OperatingSystem.windows,
      () => DynamicLibrary.open(libraryPath),
    );
  } else {
    throw UnsupportedError(
      'Unsupported platform: ${Platform.operatingSystem}',
    );
  }
  print('SQLCipher configured with library at: $libraryPath');
}
