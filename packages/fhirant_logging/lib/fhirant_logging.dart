import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';

/// Singleton Logging Service for structured logs
class FhirantLogging {
  /// Factory constructor to return the singleton instance
  factory FhirantLogging() => _instance;

  // Private constructor to ensure Singleton
  FhirantLogging._internal();

  static final FhirantLogging _instance = FhirantLogging._internal();

  static final Logger _logger = Logger('FHIRantServer');

  String? _logFilePath;

  /// Initialize logging (should be called once in `main`).
  ///
  /// [logFilePath] — path for the log file. Pass `null` to disable file
  /// logging (useful on mobile). Defaults to `'server_logs.json'` for
  /// backwards-compatible CLI usage.
  void initialize({String? logFilePath = 'server_logs.json'}) {
    _logFilePath = logFilePath;
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

  /// Write log message to a file (no-op if [_logFilePath] is null)
  void _writeToFile(String logMessage) {
    if (_logFilePath == null) return;
    File(
      _logFilePath!,
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
