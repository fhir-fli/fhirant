import 'dart:convert';
import 'dart:io';

import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:test/test.dart';

/// Reads the log file back and returns one decoded record per line.
List<Map<String, dynamic>> readRecords(File file) {
  if (!file.existsSync()) return <Map<String, dynamic>>[];
  return file
      .readAsLinesSync()
      .where((line) => line.trim().isNotEmpty)
      .map((line) => jsonDecode(line) as Map<String, dynamic>)
      .toList();
}

void main() {
  late Directory tempDir;
  late File logFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('fhirant_logging_test');
    logFile = File('${tempDir.path}/server_logs.json');
    FhirantLogging().initialize(logFilePath: logFile.path);
  });

  tearDown(() {
    // Detach file logging so a later test in the same process does not append
    // to a directory that is about to be deleted.
    FhirantLogging().initialize(logFilePath: null);
    tempDir.deleteSync(recursive: true);
  });

  test('logInfo writes one INFO record carrying the message', () {
    FhirantLogging().logInfo('server started');

    final records = readRecords(logFile);
    expect(records, hasLength(1));
    expect(records.single['level'], 'INFO');
    expect(records.single['message'], 'server started');
    expect(records.single['error'], isNull);
    expect(records.single['stackTrace'], isNull);
    expect(
      DateTime.parse(records.single['timestamp'] as String),
      isA<DateTime>(),
    );
  });

  test('logWarning writes WARNING and logError writes SEVERE', () {
    FhirantLogging().logWarning('disk is nearly full');
    FhirantLogging().logError('write failed');

    final records = readRecords(logFile);
    expect(records.map((r) => r['level']), ['WARNING', 'SEVERE']);
    expect(records.first['message'], 'disk is nearly full');
    expect(records.last['message'], 'write failed');
  });

  test('logError carries the error and the stack trace', () {
    final trace = StackTrace.fromString('#0  frame one\n#1  frame two');
    FhirantLogging()
        .logError('save failed', const FormatException('bad'), trace);

    final records = readRecords(logFile);
    expect(records, hasLength(1));
    expect(records.single['error'], contains('bad'));
    expect(records.single['stackTrace'], contains('frame one'));
  });

  test('a null log file path writes no file', () {
    FhirantLogging().initialize(logFilePath: null);
    FhirantLogging().logInfo('goes to stdout only');

    expect(logFile.existsSync(), isFalse);
  });

  test('initializing twice still writes each message once', () {
    // Every initialize() used to add another Logger.root.onRecord listener,
    // and each listener wrote the same line to whichever file was current.
    // The app initializes once, but the server tests initialize per test in
    // one process, so the duplicates landed in the file a security test reads.
    FhirantLogging().initialize(logFilePath: logFile.path);
    FhirantLogging().initialize(logFilePath: logFile.path);

    FhirantLogging().logInfo('said once');

    final records = readRecords(logFile);
    expect(records, hasLength(1));
    expect(records.single['message'], 'said once');
  });

  test('after re-initializing, the earlier file stops receiving records', () {
    final second = File('${tempDir.path}/second_logs.json');
    FhirantLogging().initialize(logFilePath: second.path);

    FhirantLogging().logInfo('after the switch');

    expect(readRecords(second).map((r) => r['message']), ['after the switch']);
    expect(readRecords(logFile), isEmpty);
  });
}
