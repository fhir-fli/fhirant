import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';

/// Singleton Logging Service for structured logs
class FhirAntLoggingService {
  /// Factory constructor to return the singleton instance
  factory FhirAntLoggingService() => _instance;

  // Private constructor to ensure Singleton
  FhirAntLoggingService._internal();

  static final FhirAntLoggingService _instance =
      FhirAntLoggingService._internal();

  static final Logger _logger = Logger('FHIRantServer');

  /// Initialize logging (should be called once in `main`)
  void initialize() {
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
      print(logMessage);

      // Write to a log file (flush after each log for real-time logging)
      _writeToFile(logMessage);
    });
  }

  /// Write log message to a file
  void _writeToFile(String logMessage) {
    File(
      'server_logs.json',
    ).writeAsStringSync('$logMessage\n', mode: FileMode.append);
  }

  /// Log general information
  void logInfo(String message) {
    _logger.info(message);
  }

  /// Log warnings
  void logWarning(String message) {
    _logger.warning(message);
  }

  /// Log errors
  void logError(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.severe(message, error, stackTrace);
  }
}
