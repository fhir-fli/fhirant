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

  /// The most bytes the log file grows to before it is rotated: the file is
  /// renamed to `<path>.1` (replacing the previous `.1`) and a new one
  /// started, so the app carries at most two files of this size. Five
  /// megabytes is a choice; on the phone the file used to grow without
  /// bound (REVIEW-2026-09-06 finding 42).
  static const int defaultMaxBytes = 5 * 1024 * 1024;

  String? _logFilePath;
  int _maxBytes = defaultMaxBytes;

  /// The open file sink. Lines are handed to it and written by the IO
  /// thread; the caller never waits on the disk. The old code opened the
  /// file and appended synchronously per line, on the UI isolate in the app.
  IOSink? _sink;

  /// Bytes written to the current file (its length at open, then each line).
  int _bytes = 0;

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
  /// backwards-compatible CLI usage. [maxBytes] caps the file; see
  /// [defaultMaxBytes].
  ///
  /// Calling this again replaces the previous configuration; it does not add
  /// to it. What the previous sink still held is flushed and closed.
  void initialize({
    String? logFilePath = 'server_logs.json',
    int maxBytes = defaultMaxBytes,
  }) {
    _closeSink();
    _logFilePath = logFilePath;
    _maxBytes = maxBytes;
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

      _writeToFile(logMessage);
    });
  }

  /// Completes when everything logged so far is in the file. For tests and
  /// for an orderly shutdown; nothing on the request path waits on it.
  Future<void> flush() async {
    await _sink?.flush();
  }

  /// Opens the file on the first line written to it, so a configured path
  /// that is never logged to (or a test's replaced one) creates no file.
  IOSink _openSink(String path) {
    final file = File(path);
    _bytes = file.existsSync() ? file.lengthSync() : 0;
    return _sink = file.openWrite(mode: FileMode.append);
  }

  void _closeSink() {
    final sink = _sink;
    _sink = null;
    if (sink != null) {
      // Close flushes what the sink holds; errors on a file that has gone
      // (a test directory deleted under it) are not the logger's to raise.
      unawaited(sink.close().catchError((_) {}));
    }
  }

  /// Hands one line to the sink, rotating the file first when the line
  /// would take it past the cap.
  void _writeToFile(String logMessage) {
    final path = _logFilePath;
    if (path == null) return;
    final sink = _sink ?? _openSink(path);
    final line = '$logMessage\n';
    final size = utf8.encode(line).length;
    if (_bytes > 0 && _bytes + size > _maxBytes) {
      _rotate(path).write(line);
    } else {
      sink.write(line);
    }
    _bytes += size;
  }

  /// `<path>` becomes `<path>.1`, replacing the previous `.1`, and a new
  /// file is started. Done synchronously, once per [_maxBytes] of logging,
  /// so the order of lines across the two files is exact.
  IOSink _rotate(String path) {
    final sink = _sink;
    _sink = null;
    if (sink != null) {
      unawaited(sink.close().catchError((_) {}));
    }
    final file = File(path);
    final previous = File('$path.1');
    try {
      if (previous.existsSync()) previous.deleteSync();
      if (file.existsSync()) file.renameSync(previous.path);
    } on FileSystemException {
      // If the rename fails the new sink appends to the same file; the
      // next line tries again.
    }
    _bytes = 0;
    return _sink = file.openWrite(mode: FileMode.append);
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
