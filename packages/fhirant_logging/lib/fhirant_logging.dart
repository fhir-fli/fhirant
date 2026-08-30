import 'dart:async';
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

  /// The listener on [Logger.root]. Held so that a second [initialize] can
  /// replace it rather than add a second one: `onRecord` is a broadcast
  /// stream, so every extra subscription wrote the same record again, and the
  /// duplicates landed in the file and on stdout. The app initializes once,
  /// but tests initialize per test in a single process, which is where this
  /// showed: `dart test` on this package saw one line become ten.
  StreamSubscription<LogRecord>? _subscription;

  /// Initialize logging (should be called once in `main`).
  ///
  /// [logFilePath] — path for the log file. Pass `null` to disable file
  /// logging (useful on mobile). Defaults to `'server_logs.json'` for
  /// backwards-compatible CLI usage.
  ///
  /// Calling this again replaces the previous configuration; it does not add
  /// to it.
  void initialize({String? logFilePath = 'server_logs.json'}) {
    _logFilePath = logFilePath;
    Logger.root.level = Level.ALL; // Log everything
    unawaited(_subscription?.cancel());
    _subscription = Logger.root.onRecord.listen((record) {
      final logMessage = jsonEncode({
        'timestamp': record.time.toIso8601String(),
        'level': record.level.name,
        'message': record.message,
        'error': record.error?.toString(),
        'stackTrace': record.stackTrace?.toString(),
      });

      // Write to console (stdout is the logger's own sink here; using the
      // FhirantLogging API would recurse into this same listener).
      stdout.writeln(logMessage);

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
