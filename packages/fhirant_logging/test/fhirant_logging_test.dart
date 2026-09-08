import 'dart:convert';
import 'dart:io';

import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:test/test.dart';

/// The records in [file] once the sink has written everything logged.
Future<List<Map<String, dynamic>>> flushed(File file) async {
  await FhirantLogging().flush();
  return readRecords(file);
}

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

  tearDown(() async {
    // Detach file logging so a later test in the same process does not append
    // to a directory that is about to be deleted.
    await FhirantLogging().flush();
    FhirantLogging().initialize(logFilePath: null);
    tempDir.deleteSync(recursive: true);
  });

  test('the file is capped: past maxBytes it rotates to .1 and starts over',
      () async {
    FhirantLogging().initialize(logFilePath: logFile.path, maxBytes: 2000);
    for (var i = 0; i < 40; i++) {
      FhirantLogging().logInfo('line $i ${'x' * 100}');
    }
    await FhirantLogging().flush();
    final previous = File('${logFile.path}.1');
    expect(previous.existsSync(), isTrue);
    expect(logFile.lengthSync(), lessThanOrEqualTo(2000));
    expect(previous.lengthSync(), lessThanOrEqualTo(2000));
    final all = [...readRecords(previous), ...readRecords(logFile)];
    // Only the last two files are kept, so the earliest lines are gone.
    expect(all.length, lessThan(40));
    expect(all.last['message'], startsWith('line 39 '));
    expect(File('${logFile.path}.2').existsSync(), isFalse);
  });

  test('the cap counts what the file already held', () async {
    logFile.writeAsStringSync('x' * 1900);
    FhirantLogging().initialize(logFilePath: logFile.path, maxBytes: 2000);
    FhirantLogging().logInfo('a line longer than the hundred bytes left');
    await FhirantLogging().flush();
    expect(File('${logFile.path}.1').lengthSync(), 1900);
    expect(readRecords(logFile), hasLength(1));
  });

  test('logInfo writes one INFO record carrying the message', () async {
    FhirantLogging().logInfo('server started');

    final records = await flushed(logFile);
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

  test('logWarning writes WARNING and logError writes SEVERE', () async {
    FhirantLogging().logWarning('disk is nearly full');
    FhirantLogging().logError('write failed');

    final records = await flushed(logFile);
    expect(records.map((r) => r['level']), ['WARNING', 'SEVERE']);
    expect(records.first['message'], 'disk is nearly full');
    expect(records.last['message'], 'write failed');
  });

  test('logError carries the error and the stack trace', () async {
    final trace = StackTrace.fromString('#0  frame one\n#1  frame two');
    FhirantLogging()
        .logError('save failed', const FormatException('bad'), trace);

    final records = await flushed(logFile);
    expect(records, hasLength(1));
    expect(records.single['error'], contains('bad'));
    expect(records.single['stackTrace'], contains('frame one'));
  });

  test('a null log file path writes no file', () async {
    FhirantLogging().initialize(logFilePath: null);
    FhirantLogging().logInfo('goes to stdout only');

    expect(logFile.existsSync(), isFalse);
  });

  test('initializing twice still writes each message once', () async {
    // Every initialize() used to add another Logger.root.onRecord listener,
    // and each listener wrote the same line to whichever file was current.
    // The app initializes once, but the server tests initialize per test in
    // one process, so the duplicates landed in the file a security test reads.
    FhirantLogging().initialize(logFilePath: logFile.path);
    FhirantLogging().initialize(logFilePath: logFile.path);

    FhirantLogging().logInfo('said once');

    final records = await flushed(logFile);
    expect(records, hasLength(1));
    expect(records.single['message'], 'said once');
  });

  test('after re-initializing, the earlier file stops receiving records',
      () async {
    final second = File('${tempDir.path}/second_logs.json');
    FhirantLogging().initialize(logFilePath: second.path);

    FhirantLogging().logInfo('after the switch');

    expect(
      (await flushed(second)).map((r) => r['message']),
      ['after the switch'],
    );
    expect(await flushed(logFile), isEmpty);
  });
}
