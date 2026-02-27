// ignore_for_file: lines_longer_than_80_chars
import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shelf/shelf.dart';

import 'package:fhirant_server/src/handlers/export_handler.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

void main() {
  late MockFhirAntDb mockDb;
  late String exportDir;

  setUp(() async {
    mockDb = MockFhirAntDb();
    exportDir = '${Directory.systemTemp.path}/fhirant_export_test_${DateTime.now().millisecondsSinceEpoch}';
  });

  tearDown(() async {
    final dir = Directory(exportDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  void _stubCreateExportJob() {
    when(() => mockDb.createExportJob(
      jobId: any(named: 'jobId'),
      status: any(named: 'status'),
      requestUrl: any(named: 'requestUrl'),
      transactionTime: any(named: 'transactionTime'),
      resourceTypes: any(named: 'resourceTypes'),
      since: any(named: 'since'),
      exportLevel: any(named: 'exportLevel'),
      patientId: any(named: 'patientId'),
      groupId: any(named: 'groupId'),
      typeFilters: any(named: 'typeFilters'),
      requestedBy: any(named: 'requestedBy'),
    )).thenAnswer((_) async {});
  }

  Request _makeRequest(
    String path, {
    Map<String, String>? headers,
    String method = 'GET',
  }) {
    return Request(
      method,
      Uri.parse('http://localhost:8080$path'),
      headers: headers ?? {},
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Kick-off handler
  // ─────────────────────────────────────────────────────────────────────────
  group('exportKickoffHandler', () {
    test('returns 400 when Prefer: respond-async header is missing', () async {
      final request = _makeRequest('/\$export');

      final response = await exportKickoffHandler(
        request,
        mockDb,
        exportDir,
      );

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], equals('OperationOutcome'));
    });

    test('returns 400 for unsupported _outputFormat', () async {
      final request = _makeRequest(
        '/\$export?_outputFormat=text/csv',
        headers: {'prefer': 'respond-async'},
      );

      final response = await exportKickoffHandler(
        request,
        mockDb,
        exportDir,
      );

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['issue'][0]['diagnostics'], contains('_outputFormat'));
    });

    test('returns 400 for invalid _since value', () async {
      final request = _makeRequest(
        '/\$export?_since=not-a-date',
        headers: {'prefer': 'respond-async'},
      );

      final response = await exportKickoffHandler(
        request,
        mockDb,
        exportDir,
      );

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['issue'][0]['diagnostics'], contains('_since'));
    });

    test('returns 202 with Content-Location on valid kick-off', () async {
      final request = _makeRequest(
        '/\$export',
        headers: {'prefer': 'respond-async'},
      );

      _stubCreateExportJob();
      when(() => mockDb.updateExportJob(any(), status: any(named: 'status')))
          .thenAnswer((_) async {});
      when(() => mockDb.getExportJob(any())).thenAnswer((_) async => null);

      final response = await exportKickoffHandler(
        request,
        mockDb,
        exportDir,
      );

      expect(response.statusCode, equals(202));
      expect(response.headers['content-location'], isNotNull);
      expect(
        response.headers['content-location'],
        contains('\$export-poll-status/'),
      );
    });

    test('accepts valid _outputFormat', () async {
      final request = _makeRequest(
        '/\$export?_outputFormat=application/fhir%2Bndjson',
        headers: {'prefer': 'respond-async'},
      );

      _stubCreateExportJob();
      when(() => mockDb.updateExportJob(any(), status: any(named: 'status')))
          .thenAnswer((_) async {});
      when(() => mockDb.getExportJob(any())).thenAnswer((_) async => null);

      final response = await exportKickoffHandler(
        request,
        mockDb,
        exportDir,
      );

      expect(response.statusCode, equals(202));
    });

    test('returns 400 for invalid _typeFilter format', () async {
      final request = _makeRequest(
        '/\$export?_typeFilter=InvalidNoQuestionMark',
        headers: {'prefer': 'respond-async'},
      );

      final response = await exportKickoffHandler(
        request,
        mockDb,
        exportDir,
      );

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['issue'][0]['diagnostics'], contains('_typeFilter'));
    });

    test('returns 400 for invalid resource type in _typeFilter', () async {
      final request = _makeRequest(
        '/\$export?_typeFilter=FakeResource%3Fcode%3Dabc',
        headers: {'prefer': 'respond-async'},
      );

      final response = await exportKickoffHandler(
        request,
        mockDb,
        exportDir,
      );

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['issue'][0]['diagnostics'], contains('FakeResource'));
    });

    test('passes _typeFilter to job', () async {
      final request = _makeRequest(
        '/\$export?_typeFilter=Condition%3Fcategory%3Dproblem-list-item',
        headers: {'prefer': 'respond-async'},
      );

      String? capturedTypeFilters;
      when(() => mockDb.createExportJob(
        jobId: any(named: 'jobId'),
        status: any(named: 'status'),
        requestUrl: any(named: 'requestUrl'),
        transactionTime: any(named: 'transactionTime'),
        resourceTypes: any(named: 'resourceTypes'),
        since: any(named: 'since'),
        exportLevel: any(named: 'exportLevel'),
        patientId: any(named: 'patientId'),
        groupId: any(named: 'groupId'),
        typeFilters: any(named: 'typeFilters'),
        requestedBy: any(named: 'requestedBy'),
      )).thenAnswer((inv) async {
        capturedTypeFilters = inv.namedArguments[#typeFilters] as String?;
      });
      when(() => mockDb.updateExportJob(any(), status: any(named: 'status')))
          .thenAnswer((_) async {});
      when(() => mockDb.getExportJob(any())).thenAnswer((_) async => null);

      final response = await exportKickoffHandler(
        request,
        mockDb,
        exportDir,
      );

      expect(response.statusCode, equals(202));
      expect(capturedTypeFilters, isNotNull);
      final filters = jsonDecode(capturedTypeFilters!) as List;
      expect(filters, contains('Condition?category=problem-list-item'));
    });

    test('accepts valid _typeFilter and returns 202', () async {
      final request = _makeRequest(
        '/\$export?_typeFilter=Observation%3Fcategory%3Dvital-signs',
        headers: {'prefer': 'respond-async'},
      );

      _stubCreateExportJob();
      when(() => mockDb.updateExportJob(any(), status: any(named: 'status')))
          .thenAnswer((_) async {});
      when(() => mockDb.getExportJob(any())).thenAnswer((_) async => null);

      final response = await exportKickoffHandler(
        request,
        mockDb,
        exportDir,
      );

      expect(response.statusCode, equals(202));
    });

    test('passes _type parameter to job', () async {
      final request = _makeRequest(
        '/\$export?_type=Patient,Observation',
        headers: {'prefer': 'respond-async'},
      );

      String? capturedResourceTypes;
      when(() => mockDb.createExportJob(
        jobId: any(named: 'jobId'),
        status: any(named: 'status'),
        requestUrl: any(named: 'requestUrl'),
        transactionTime: any(named: 'transactionTime'),
        resourceTypes: any(named: 'resourceTypes'),
        since: any(named: 'since'),
        exportLevel: any(named: 'exportLevel'),
        patientId: any(named: 'patientId'),
        groupId: any(named: 'groupId'),
        typeFilters: any(named: 'typeFilters'),
        requestedBy: any(named: 'requestedBy'),
      )).thenAnswer((inv) async {
        capturedResourceTypes = inv.namedArguments[#resourceTypes] as String?;
      });
      when(() => mockDb.updateExportJob(any(), status: any(named: 'status')))
          .thenAnswer((_) async {});
      when(() => mockDb.getExportJob(any())).thenAnswer((_) async => null);

      final response = await exportKickoffHandler(
        request,
        mockDb,
        exportDir,
      );

      expect(response.statusCode, equals(202));
      expect(capturedResourceTypes, equals('Patient,Observation'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Group-level kick-off
  // ─────────────────────────────────────────────────────────────────────────
  group('Group-level exportKickoffHandler', () {
    test('returns 404 when Group not found', () async {
      final request = _makeRequest(
        '/Group/g1/\$export',
        headers: {'prefer': 'respond-async'},
      );

      when(() => mockDb.getResource(fhir.R4ResourceType.FhirGroup, 'g1'))
          .thenAnswer((_) async => null);

      final response = await exportKickoffHandler(
        request,
        mockDb,
        exportDir,
        exportLevel: 'group',
        groupId: 'g1',
      );

      expect(response.statusCode, equals(404));
      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], equals('OperationOutcome'));
      expect(body['issue'][0]['diagnostics'], contains('Group not found'));
    });

    test('returns 202 on valid group export kick-off', () async {
      final request = _makeRequest(
        '/Group/g1/\$export',
        headers: {'prefer': 'respond-async'},
      );

      final group = fhir.FhirGroup(
        id: 'g1'.toFhirString,
        type: fhir.GroupType.person,
        actual: true.toFhirBoolean,
        member: [
          fhir.GroupMember(
            entity: fhir.Reference(reference: 'Patient/p1'.toFhirString),
          ),
        ],
      );

      when(() => mockDb.getResource(fhir.R4ResourceType.FhirGroup, 'g1'))
          .thenAnswer((_) async => group);
      _stubCreateExportJob();
      when(() => mockDb.updateExportJob(any(), status: any(named: 'status')))
          .thenAnswer((_) async {});
      when(() => mockDb.getExportJob(any())).thenAnswer((_) async => null);

      final response = await exportKickoffHandler(
        request,
        mockDb,
        exportDir,
        exportLevel: 'group',
        groupId: 'g1',
      );

      expect(response.statusCode, equals(202));
      expect(response.headers['content-location'], isNotNull);
      expect(
        response.headers['content-location'],
        contains('\$export-poll-status/'),
      );
    });

    test('stores groupId in export job', () async {
      final request = _makeRequest(
        '/Group/g1/\$export',
        headers: {'prefer': 'respond-async'},
      );

      final group = fhir.FhirGroup(
        id: 'g1'.toFhirString,
        type: fhir.GroupType.person,
        actual: true.toFhirBoolean,
      );

      String? capturedGroupId;
      String? capturedExportLevel;
      when(() => mockDb.getResource(fhir.R4ResourceType.FhirGroup, 'g1'))
          .thenAnswer((_) async => group);
      when(() => mockDb.createExportJob(
        jobId: any(named: 'jobId'),
        status: any(named: 'status'),
        requestUrl: any(named: 'requestUrl'),
        transactionTime: any(named: 'transactionTime'),
        resourceTypes: any(named: 'resourceTypes'),
        since: any(named: 'since'),
        exportLevel: any(named: 'exportLevel'),
        patientId: any(named: 'patientId'),
        groupId: any(named: 'groupId'),
        typeFilters: any(named: 'typeFilters'),
        requestedBy: any(named: 'requestedBy'),
      )).thenAnswer((inv) async {
        capturedGroupId = inv.namedArguments[#groupId] as String?;
        capturedExportLevel = inv.namedArguments[#exportLevel] as String?;
      });
      when(() => mockDb.updateExportJob(any(), status: any(named: 'status')))
          .thenAnswer((_) async {});
      when(() => mockDb.getExportJob(any())).thenAnswer((_) async => null);

      final response = await exportKickoffHandler(
        request,
        mockDb,
        exportDir,
        exportLevel: 'group',
        groupId: 'g1',
      );

      expect(response.statusCode, equals(202));
      expect(capturedGroupId, equals('g1'));
      expect(capturedExportLevel, equals('group'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Status handler
  // ─────────────────────────────────────────────────────────────────────────
  group('exportStatusHandler', () {
    test('returns 404 for unknown job', () async {
      final request = _makeRequest('/\$export-poll-status/unknown-id');
      when(() => mockDb.getExportJob('unknown-id'))
          .thenAnswer((_) async => null);

      final response = await exportStatusHandler(request, mockDb, 'unknown-id');

      expect(response.statusCode, equals(404));
    });

    test('returns 202 when job is pending', () async {
      final request = _makeRequest('/\$export-poll-status/job-1');
      when(() => mockDb.getExportJob('job-1')).thenAnswer((_) async =>
          _fakeExportJob(jobId: 'job-1', status: 'pending'));

      final response = await exportStatusHandler(request, mockDb, 'job-1');

      expect(response.statusCode, equals(202));
      expect(response.headers['x-progress'], equals('Queued'));
    });

    test('returns 202 when job is in_progress', () async {
      final request = _makeRequest('/\$export-poll-status/job-1');
      when(() => mockDb.getExportJob('job-1')).thenAnswer((_) async =>
          _fakeExportJob(jobId: 'job-1', status: 'in_progress'));

      final response = await exportStatusHandler(request, mockDb, 'job-1');

      expect(response.statusCode, equals(202));
      expect(response.headers['x-progress'], equals('Exporting...'));
    });

    test('returns 200 with manifest when job is completed', () async {
      final request = _makeRequest('/\$export-poll-status/job-1');
      final outputJson = jsonEncode([
        {
          'type': 'Patient',
          'url': 'http://localhost:8080/\$export-file/job-1/Patient.ndjson',
          'count': 5,
        },
      ]);
      when(() => mockDb.getExportJob('job-1')).thenAnswer((_) async =>
          _fakeExportJob(
            jobId: 'job-1',
            status: 'completed',
            outputJson: outputJson,
            completedAt: DateTime.now(),
          ));

      final response = await exportStatusHandler(request, mockDb, 'job-1');

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['output'], isList);
      expect(body['output'].length, equals(1));
      expect(body['output'][0]['type'], equals('Patient'));
      expect(body['output'][0]['count'], equals(5));
      expect(body['requiresAccessToken'], isTrue);
      expect(body['transactionTime'], isNotNull);
    });

    test('returns 500 when job has error', () async {
      final request = _makeRequest('/\$export-poll-status/job-1');
      when(() => mockDb.getExportJob('job-1')).thenAnswer((_) async =>
          _fakeExportJob(
            jobId: 'job-1',
            status: 'error',
            errorJson: jsonEncode([
              {
                'resourceType': 'OperationOutcome',
                'issue': [
                  {'severity': 'error', 'code': 'exception', 'diagnostics': 'Something went wrong'},
                ],
              },
            ]),
          ));

      final response = await exportStatusHandler(request, mockDb, 'job-1');

      expect(response.statusCode, equals(500));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], isList);
      expect(body['error'].length, equals(1));
    });

    test('returns 404 for cancelled job', () async {
      final request = _makeRequest('/\$export-poll-status/job-1');
      when(() => mockDb.getExportJob('job-1')).thenAnswer((_) async =>
          _fakeExportJob(jobId: 'job-1', status: 'cancelled'));

      final response = await exportStatusHandler(request, mockDb, 'job-1');

      expect(response.statusCode, equals(404));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // File download handler
  // ─────────────────────────────────────────────────────────────────────────
  group('exportFileHandler', () {
    test('returns 404 when file does not exist', () async {
      final request = _makeRequest('/\$export-file/job-1/Patient.ndjson');

      final response = await exportFileHandler(
        request,
        exportDir,
        'job-1',
        'Patient.ndjson',
      );

      expect(response.statusCode, equals(404));
    });

    test('returns 400 for path traversal attempt', () async {
      final request = _makeRequest('/\$export-file/job-1/../../../etc/passwd');

      final response = await exportFileHandler(
        request,
        exportDir,
        'job-1',
        '../../../etc/passwd',
      );

      expect(response.statusCode, equals(400));
    });

    test('serves NDJSON file when it exists', () async {
      // Create a test NDJSON file
      final jobDir = Directory('$exportDir/job-1');
      await jobDir.create(recursive: true);
      final file = File('${jobDir.path}/Patient.ndjson');
      final patient = fhir.Patient(
        id: 'p1'.toFhirString,
        name: [fhir.HumanName(family: 'Test'.toFhirString)],
      );
      await file.writeAsString('${jsonEncode(patient.toJson())}\n');

      final request = _makeRequest('/\$export-file/job-1/Patient.ndjson');
      final response = await exportFileHandler(
        request,
        exportDir,
        'job-1',
        'Patient.ndjson',
      );

      expect(response.statusCode, equals(200));
      expect(
        response.headers['content-type'],
        equals('application/fhir+ndjson'),
      );
      final content = await response.readAsString();
      expect(content, contains('"resourceType":"Patient"'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Delete/Cancel handler
  // ─────────────────────────────────────────────────────────────────────────
  group('exportDeleteHandler', () {
    test('returns 404 for unknown job', () async {
      final request = _makeRequest(
        '/\$export-poll-status/unknown-id',
        method: 'DELETE',
      );
      when(() => mockDb.getExportJob('unknown-id'))
          .thenAnswer((_) async => null);

      final response =
          await exportDeleteHandler(request, mockDb, exportDir, 'unknown-id');

      expect(response.statusCode, equals(404));
    });

    test('cancels job and returns 202', () async {
      final request = _makeRequest(
        '/\$export-poll-status/job-1',
        method: 'DELETE',
      );
      when(() => mockDb.getExportJob('job-1')).thenAnswer((_) async =>
          _fakeExportJob(jobId: 'job-1', status: 'in_progress'));
      when(() => mockDb.updateExportJob('job-1', status: 'cancelled'))
          .thenAnswer((_) async {});
      when(() => mockDb.deleteExportJob('job-1')).thenAnswer((_) async {});

      final response =
          await exportDeleteHandler(request, mockDb, exportDir, 'job-1');

      expect(response.statusCode, equals(202));
      verify(() => mockDb.updateExportJob('job-1', status: 'cancelled'))
          .called(1);
      verify(() => mockDb.deleteExportJob('job-1')).called(1);
    });

    test('cleans up export files on delete', () async {
      // Create job directory with a file
      final jobDir = Directory('$exportDir/job-1');
      await jobDir.create(recursive: true);
      await File('${jobDir.path}/Patient.ndjson').writeAsString('test');

      final request = _makeRequest(
        '/\$export-poll-status/job-1',
        method: 'DELETE',
      );
      when(() => mockDb.getExportJob('job-1')).thenAnswer((_) async =>
          _fakeExportJob(jobId: 'job-1', status: 'completed'));
      when(() => mockDb.updateExportJob('job-1', status: 'cancelled'))
          .thenAnswer((_) async {});
      when(() => mockDb.deleteExportJob('job-1')).thenAnswer((_) async {});

      final response =
          await exportDeleteHandler(request, mockDb, exportDir, 'job-1');

      expect(response.statusCode, equals(202));
      expect(await jobDir.exists(), isFalse);
    });
  });
}

/// Creates a fake ExportJob for testing status handler responses.
ExportJob _fakeExportJob({
  required String jobId,
  required String status,
  String? outputJson,
  String? errorJson,
  DateTime? completedAt,
  String? groupId,
  String exportLevel = 'system',
  String? typeFilters,
}) {
  return ExportJob(
    jobId: jobId,
    status: status,
    requestUrl: 'http://localhost:8080/\$export',
    transactionTime: DateTime(2026, 2, 8),
    createdAt: DateTime(2026, 2, 8),
    completedAt: completedAt,
    outputJson: outputJson,
    errorJson: errorJson,
    resourceTypes: null,
    since: null,
    exportLevel: exportLevel,
    patientId: null,
    groupId: groupId,
    typeFilters: typeFilters,
    requestedBy: null,
  );
}
