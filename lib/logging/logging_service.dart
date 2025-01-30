import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';

/// Logging Service for structured logs
class LoggingService {
  static final Logger _logger = Logger('FHIRantServer');

  /// Initialize logging (should be called once in `main`)
  static void initialize() {
    Logger.root.level = Level.ALL; // Log everything
    Logger.root.onRecord.listen((LogRecord record) {
      final logMessage = jsonEncode({
        'timestamp': record.time.toIso8601String(),
        'level': record.level.name,
        'message': record.message,
        'error': record.error?.toString(),
        'stackTrace': record.stackTrace?.toString(),
      });

      // Print to console
      // ignore: avoid_print
      print(logMessage);

      // Write to a log file
      _writeToFile(logMessage);
    });
  }

  /// Write log message to a file
  static void _writeToFile(String logMessage) {
    File(
      'server_logs.json',
    ).writeAsStringSync('$logMessage\n', mode: FileMode.append);
  }

  /// Log general information
  static void logInfo(String message) {
    _logger.info(message);
  }

  /// Log warnings
  static void logWarning(String message) {
    _logger.warning(message);
  }

  /// Log errors
  static void logError(
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    _logger.severe(message, error, stackTrace);
  }
}
