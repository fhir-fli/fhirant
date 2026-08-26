import 'dart:io';

import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// Regression guard for finding F6 of SECURITY-REVIEW-2026-08-25.md.
///
/// This began as evidence: it drove a real request through the real pipeline
/// with file logging enabled the way the app enables it, read the file back,
/// and found `?name=Faulkenberry&birthdate=1974-12-25` written verbatim into a
/// plaintext file beside the encrypted database.
///
/// The values are redacted now, so the assertions are inverted. It still goes
/// through the whole pipeline and reads the actual file, because the claim
/// worth guarding is what lands on disk, not what the logging code appears to
/// do.
void main() {
  late Directory tempDir;
  late File logFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('fhirant_log_test');
    logFile = File('${tempDir.path}/server_logs.json');
    FhirantLogging().initialize(logFilePath: logFile.path);
  });

  tearDown(() {
    // Detach file logging so later tests in the same process do not append.
    FhirantLogging().initialize(logFilePath: null);
    tempDir.deleteSync(recursive: true);
  });

  test('search parameter values do not reach the log file', () async {
    final server = await createTestServer();
    final token = generateTestToken(scopes: ['user/*.rs']);

    await server.handler(
      testRequest(
        'GET',
        '/Patient?name=Faulkenberry&birthdate=1974-12-25',
        authToken: token,
      ),
    );

    final contents = logFile.readAsStringSync();

    expect(
      contents,
      isNot(contains('Faulkenberry')),
      reason: 'a name in a plaintext file beside the encrypted database undoes '
          'the point of encrypting it',
    );
    expect(contents, isNot(contains('1974-12-25')));

    // The parameter names survive: which search was run is the diagnostic
    // value, and it identifies nobody.
    expect(contents, contains('name=[redacted]'));
    expect(contents, contains('birthdate=[redacted]'));
    expect(contents, contains('/Patient'));
  });

  test('a resource id is still logged, deliberately', () async {
    // Ids say which record was touched, which is most of what makes the log
    // useful for working out what happened on a device, and on their own they
    // do not name a person the way a search on name and birth date does. This
    // is a decision, so it is pinned rather than left to drift.
    final server = await createTestServer();
    final token = generateTestToken(scopes: ['user/*.rs']);

    await server.handler(
      testRequest('GET', '/Patient/patient-12345', authToken: token),
    );

    expect(logFile.readAsStringSync(), contains('patient-12345'));
  });

  test('the file is still plaintext, but no longer carries the identifiers',
      () async {
    final server = await createTestServer();
    final token = generateTestToken(scopes: ['user/*.rs']);

    await server.handler(
      testRequest('GET', '/Observation?subject=Patient/abc', authToken: token),
    );

    final contents = logFile.readAsStringSync();
    // Still plaintext — F6's fix narrowed what is written, it did not encrypt
    // the file. Anyone holding the device can read it.
    expect(contents, isNotEmpty);
    expect(contents.trim().split('\n').first, startsWith('{'));
    // ...but the subject reference, which names a patient, is not in it.
    expect(contents, isNot(contains('Patient/abc')));
    expect(contents, contains('subject=[redacted]'));
  });
}
