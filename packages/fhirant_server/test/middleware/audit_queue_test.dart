import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/middlewares/audit_middleware.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

/// REVIEW-2026-09-17 A16: `AuditQueue` ignored `saveResources` answering
/// false, so a batch the store refused was lost with no line in the log.
/// The logger's own file is read back, as log_file_contents_test does:
/// the claim is what a reader of the log would see.
void main() {
  late MockFhirAntDb db;
  late Directory tempDir;
  late File logFile;

  final event = fhir.AuditEvent.fromJson({
    'resourceType': 'AuditEvent',
    'type': {
      'system': 'http://dicom.nema.org/resources/ontology/DCM',
      'code': '110112',
    },
    'recorded': '2026-09-19T00:00:00Z',
    'agent': [
      {'requestor': true},
    ],
    'source': {
      'observer': {'display': 'test'},
    },
  });

  setUpAll(() {
    registerFallbackValue(<fhir.Resource>[]);
  });

  setUp(() {
    db = MockFhirAntDb();
    tempDir = Directory.systemTemp.createTempSync('audit_queue');
    logFile = File('${tempDir.path}/server_logs.json');
    FhirantLogging().initialize(logFilePath: logFile.path);
  });

  tearDown(() {
    FhirantLogging().initialize(logFilePath: null);
    tempDir.deleteSync(recursive: true);
  });

  Future<String> logAfter(Future<void> Function() act) async {
    await act();
    await FhirantLogging().flush();
    // The file appears with the first line written; none written, no file.
    return logFile.existsSync() ? logFile.readAsStringSync() : '';
  }

  test('a batch the store refuses (false) is an error in the log', () async {
    when(() => db.saveResources(any())).thenAnswer((_) async => false);
    final queue = AuditQueue(db)..add(event);
    final log = await logAfter(queue.drain);
    expect(log, contains('Audit write of 1 event(s) failed'));
    expect(log, contains('refused the batch'));
  });

  test('a batch the store writes (true) logs nothing', () async {
    when(() => db.saveResources(any())).thenAnswer((_) async => true);
    final queue = AuditQueue(db)..add(event);
    final log = await logAfter(queue.drain);
    expect(log, isNot(contains('Audit write')));
  });

  test(
      'a batch the store throws on is an error in the log, and the queue '
      'survives', () async {
    when(() => db.saveResources(any())).thenThrow(StateError('locked'));
    final queue = AuditQueue(db)..add(event);
    final log = await logAfter(queue.drain);
    expect(log, contains('Audit write of 1 event(s) failed'));
    expect(log, contains('locked'));
  });
}
