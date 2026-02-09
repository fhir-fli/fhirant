// ignore_for_file: lines_longer_than_80_chars
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/utils/compartment_definitions.dart';
import 'package:fhirant_server/src/utils/ndjson_writer.dart';
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

const _validFormats = [
  'application/fhir+ndjson',
  'application/ndjson',
  'ndjson',
];

/// Handler for `GET /$export` (system-level), `GET /Patient/$export` (patient-level),
/// and `GET /Group/<id>/$export` (group-level).
///
/// Validates the Prefer header, parses query parameters, creates an export job,
/// and spawns a background future to process the export.
Future<Response> exportKickoffHandler(
  Request request,
  FhirAntDb dbInterface,
  String exportDir, {
  String exportLevel = 'system',
  String? patientId,
  String? groupId,
}) async {
  try {
    // 1. Validate Prefer: respond-async header
    final prefer = request.headers['prefer'] ?? '';
    if (!prefer.contains('respond-async')) {
      return _operationOutcome(
        400,
        'Bulk data export requires the Prefer: respond-async header.',
      );
    }

    // 2. Parse _outputFormat (optional, default is ndjson)
    final queryParams = request.url.queryParameters;
    final outputFormat = queryParams['_outputFormat'];
    if (outputFormat != null && !_validFormats.contains(outputFormat)) {
      return _operationOutcome(
        400,
        'Unsupported _outputFormat: $outputFormat. '
            'Supported formats: ${_validFormats.join(', ')}',
      );
    }

    // 3. Parse _type filter
    final typeParam = queryParams['_type'];

    // 4. Parse _since filter
    DateTime? since;
    final sinceParam = queryParams['_since'];
    if (sinceParam != null) {
      since = DateTime.tryParse(sinceParam);
      if (since == null) {
        return _operationOutcome(
          400,
          'Invalid _since value: $sinceParam. Expected ISO 8601 date.',
        );
      }
    }

    // 5. Validate group-level: ensure the Group resource exists
    if (exportLevel == 'group' && groupId != null) {
      final groupResource = await dbInterface.getResource(
        fhir.R4ResourceType.FhirGroup,
        groupId,
      );
      if (groupResource == null) {
        return _operationOutcome(404, 'Group not found: $groupId');
      }
    }

    // 6. Create the export job
    final jobId = const Uuid().v4();
    final transactionTime = DateTime.now().toUtc();
    final requestUrl = request.requestedUri.toString();

    await dbInterface.createExportJob(ExportJobsCompanion(
      jobId: Value(jobId),
      status: const Value('pending'),
      requestUrl: Value(requestUrl),
      transactionTime: Value(transactionTime),
      resourceTypes: Value(typeParam),
      since: Value(since),
      exportLevel: Value(exportLevel),
      patientId: Value(patientId),
      groupId: Value(groupId),
    ));

    // 7. Spawn background processing (fire-and-forget)
    _processExport(dbInterface, jobId, exportDir, request).catchError((e, st) {
      FhirantLogging().logError('Export job $jobId failed', e, st);
    });

    // 8. Return 202 Accepted with Content-Location
    final baseUrl = _baseUrl(request);
    final statusUrl = '$baseUrl/\$export-poll-status/$jobId';

    FhirantLogging().logInfo(
      'Bulk export job $jobId kicked off ($exportLevel level)',
    );

    return Response(
      202,
      headers: {
        'Content-Location': statusUrl,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'message': 'Export job accepted',
        'jobId': jobId,
      }),
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('Error in export kick-off', e, stackTrace);
    return _operationOutcome(500, 'Internal error: $e');
  }
}

/// Handler for `GET /$export-poll-status/<jobId>`.
///
/// Returns 202 while in-progress, 200 with manifest when complete,
/// 500 with error details on failure, or 404 if not found.
Future<Response> exportStatusHandler(
  Request request,
  FhirAntDb dbInterface,
  String jobId,
) async {
  try {
    final job = await dbInterface.getExportJob(jobId);
    if (job == null) {
      return _operationOutcome(404, 'Export job not found: $jobId');
    }

    switch (job.status) {
      case 'pending':
      case 'in_progress':
        return Response(
          202,
          headers: {
            'X-Progress': job.status == 'pending' ? 'Queued' : 'Exporting...',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'status': job.status}),
        );

      case 'completed':
        final manifest = <String, dynamic>{
          'transactionTime': job.transactionTime.toUtc().toIso8601String(),
          'request': job.requestUrl,
          'requiresAccessToken': true,
          'output': job.outputJson != null
              ? jsonDecode(job.outputJson!) as List<dynamic>
              : <dynamic>[],
          'error': job.errorJson != null
              ? jsonDecode(job.errorJson!) as List<dynamic>
              : <dynamic>[],
        };
        return Response.ok(
          jsonEncode(manifest),
          headers: {
            'Content-Type': 'application/json',
            'Expires': job.completedAt?.toUtc().toIso8601String() ?? '',
          },
        );

      case 'error':
        final errors = job.errorJson != null
            ? jsonDecode(job.errorJson!) as List<dynamic>
            : <dynamic>[];
        return Response(
          500,
          body: jsonEncode({
            'transactionTime': job.transactionTime.toUtc().toIso8601String(),
            'request': job.requestUrl,
            'requiresAccessToken': true,
            'output': <dynamic>[],
            'error': errors,
          }),
          headers: {'Content-Type': 'application/json'},
        );

      case 'cancelled':
        return _operationOutcome(404, 'Export job was cancelled: $jobId');

      default:
        return _operationOutcome(500, 'Unknown job status: ${job.status}');
    }
  } catch (e, stackTrace) {
    FhirantLogging().logError('Error in export status poll', e, stackTrace);
    return _operationOutcome(500, 'Internal error: $e');
  }
}

/// Handler for `GET /$export-file/<jobId>/<fileName>`.
///
/// Serves an NDJSON file from disk.
Future<Response> exportFileHandler(
  Request request,
  String exportDir,
  String jobId,
  String fileName,
) async {
  try {
    // Validate fileName to prevent path traversal
    if (fileName.contains('..') || fileName.contains('/')) {
      return _operationOutcome(400, 'Invalid file name');
    }

    final filePath = '$exportDir/$jobId/$fileName';
    final file = File(filePath);
    if (!await file.exists()) {
      return _operationOutcome(404, 'Export file not found: $fileName');
    }

    final content = await file.readAsString();
    return Response.ok(
      content,
      headers: {'Content-Type': 'application/fhir+ndjson'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('Error serving export file', e, stackTrace);
    return _operationOutcome(500, 'Internal error: $e');
  }
}

/// Handler for `DELETE /$export-poll-status/<jobId>`.
///
/// Cancels an in-progress job, deletes files, and removes the job row.
Future<Response> exportDeleteHandler(
  Request request,
  FhirAntDb dbInterface,
  String exportDir,
  String jobId,
) async {
  try {
    final job = await dbInterface.getExportJob(jobId);
    if (job == null) {
      return _operationOutcome(404, 'Export job not found: $jobId');
    }

    // Mark as cancelled (the background worker checks this)
    await dbInterface.updateExportJob(jobId, status: 'cancelled');

    // Delete output files if they exist
    final jobDir = Directory('$exportDir/$jobId');
    if (await jobDir.exists()) {
      await jobDir.delete(recursive: true);
    }

    // Remove the job row
    await dbInterface.deleteExportJob(jobId);

    FhirantLogging().logInfo('Export job $jobId cancelled and cleaned up');

    return Response(202, body: '');
  } catch (e, stackTrace) {
    FhirantLogging().logError('Error deleting export job', e, stackTrace);
    return _operationOutcome(500, 'Internal error: $e');
  }
}

/// Background worker that processes an export job.
///
/// Iterates over resource types, queries the DB, and writes NDJSON files.
Future<void> _processExport(
  FhirAntDb dbInterface,
  String jobId,
  String exportDir,
  Request request,
) async {
  try {
    // Update to in_progress
    await dbInterface.updateExportJob(jobId, status: 'in_progress');

    final job = await dbInterface.getExportJob(jobId);
    if (job == null || job.status == 'cancelled') return;

    final baseUrl = _baseUrl(request);
    final since = job.since;

    // Determine resource types to export
    List<fhir.R4ResourceType> typesToExport;
    if (job.resourceTypes != null && job.resourceTypes!.isNotEmpty) {
      typesToExport = job.resourceTypes!
          .split(',')
          .map((s) => s.trim())
          .map((s) => fhir.R4ResourceType.fromString(s))
          .whereType<fhir.R4ResourceType>()
          .toList();
    } else {
      typesToExport = await dbInterface.getResourceTypes();
    }

    final outputManifest = <Map<String, dynamic>>[];
    final errorManifest = <Map<String, dynamic>>[];

    if (job.exportLevel == 'patient') {
      // Patient-level export: restrict to Patient compartment resource types
      final definition = CompartmentDefinitions.getDefinition('Patient');
      if (definition == null) {
        await _failJob(dbInterface, jobId, 'Patient compartment not defined');
        return;
      }

      // Filter types to only those in the Patient compartment
      final compartmentTypes = definition.keys.toSet();
      if (job.resourceTypes != null && job.resourceTypes!.isNotEmpty) {
        typesToExport = typesToExport
            .where((t) => compartmentTypes.contains(t.toString()))
            .toList();
      } else {
        typesToExport = compartmentTypes
            .map((s) => fhir.R4ResourceType.fromString(s))
            .whereType<fhir.R4ResourceType>()
            .toList();
        // Only export types that actually exist in the DB
        final existingTypes = await dbInterface.getResourceTypes();
        final existingSet = existingTypes.toSet();
        typesToExport =
            typesToExport.where((t) => existingSet.contains(t)).toList();
      }
    }

    if (job.exportLevel == 'group') {
      // Group-level export: export Patient compartment resources for group members
      final definition = CompartmentDefinitions.getDefinition('Patient');
      if (definition == null) {
        await _failJob(dbInterface, jobId, 'Patient compartment not defined');
        return;
      }

      // Fetch the Group resource
      final groupResource = job.groupId != null
          ? await dbInterface.getResource(
              fhir.R4ResourceType.FhirGroup, job.groupId!)
          : null;
      if (groupResource == null) {
        await _failJob(dbInterface, jobId, 'Group not found: ${job.groupId}');
        return;
      }

      // Extract patient member references from Group.member[*].entity
      final group = groupResource as fhir.FhirGroup;
      final patientIds = group.member
              ?.map((m) => m.entity.reference?.valueString)
              .whereType<String>()
              .where((ref) => ref.startsWith('Patient/'))
              .map((ref) => ref.substring('Patient/'.length))
              .toList() ??
          [];

      if (patientIds.isEmpty) {
        // No patient members — complete with empty output
        await dbInterface.updateExportJob(
          jobId,
          status: 'completed',
          outputJson: jsonEncode(outputManifest),
          completedAt: DateTime.now().toUtc(),
        );
        FhirantLogging().logInfo(
          'Export job $jobId completed: 0 file(s) (group has no patient members)',
        );
        return;
      }

      // Determine resource types to export (Patient compartment ∩ _type filter)
      final compartmentTypes = definition.keys.toSet();
      final typeFilter = <String>[];
      if (job.resourceTypes != null && job.resourceTypes!.isNotEmpty) {
        typeFilter.addAll(job.resourceTypes!.split(',').map((s) => s.trim()));
        // Only keep types that are in the Patient compartment
        typeFilter.retainWhere((t) => compartmentTypes.contains(t));
      }

      // Aggregate resource IDs across all patient members
      final allResourceIds = <String, Set<String>>{};
      for (final patientId in patientIds) {
        // Check for cancellation
        final currentJob = await dbInterface.getExportJob(jobId);
        if (currentJob == null || currentJob.status == 'cancelled') return;

        final compartmentIds = await dbInterface.getCompartmentResourceIds(
          compartmentType: 'Patient',
          compartmentId: patientId,
          compartmentDefinition: definition,
          typeFilter: typeFilter.isNotEmpty ? typeFilter : null,
          since: since,
        );

        for (final entry in compartmentIds.entries) {
          allResourceIds.putIfAbsent(entry.key, () => {}).addAll(entry.value);
        }
      }

      // Always include Patient resources for the group members
      final shouldIncludePatient = typeFilter.isEmpty || typeFilter.contains('Patient');
      if (shouldIncludePatient) {
        allResourceIds.putIfAbsent('Patient', () => {}).addAll(patientIds.toSet());
      }

      // Fetch and write NDJSON files per resource type
      for (final entry in allResourceIds.entries) {
        final currentJob = await dbInterface.getExportJob(jobId);
        if (currentJob == null || currentJob.status == 'cancelled') return;

        final typeName = entry.key;
        final ids = entry.value;
        if (ids.isEmpty) continue;

        final resourceType = fhir.R4ResourceType.fromString(typeName);
        if (resourceType == null) continue;

        // Fetch each resource by ID
        final resources = <fhir.Resource>[];
        for (final id in ids) {
          final resource = await dbInterface.getResource(resourceType, id);
          if (resource != null) {
            // Apply _since filter for directly-included Patient resources
            if (since != null && resource.meta?.lastUpdated != null) {
              final lastUpdated = resource.meta!.lastUpdated!.valueDateTime;
              if (lastUpdated != null && lastUpdated.isBefore(since)) continue;
            }
            resources.add(resource);
          }
        }

        if (resources.isNotEmpty) {
          final count = await writeNdjsonFile(
            '$exportDir/$jobId/$typeName.ndjson',
            resources,
          );
          outputManifest.add({
            'type': typeName,
            'url': '$baseUrl/\$export-file/$jobId/$typeName.ndjson',
            'count': count,
          });
        }
      }

      // Mark job as completed
      await dbInterface.updateExportJob(
        jobId,
        status: 'completed',
        outputJson: jsonEncode(outputManifest),
        errorJson: errorManifest.isNotEmpty ? jsonEncode(errorManifest) : null,
        completedAt: DateTime.now().toUtc(),
      );

      FhirantLogging().logInfo(
        'Export job $jobId completed: ${outputManifest.length} file(s)',
      );
      return;
    }

    // Export resources (works for both system and patient level)
    for (final resourceType in typesToExport) {
      // Check for cancellation
      final currentJob = await dbInterface.getExportJob(jobId);
      if (currentJob == null || currentJob.status == 'cancelled') return;

      final resources = await dbInterface.getResourcesByTypeSince(
        resourceType,
        since: since,
      );

      if (resources.isNotEmpty) {
        final typeName = resourceType.toString();
        final count = await writeNdjsonFile(
          '$exportDir/$jobId/$typeName.ndjson',
          resources,
        );
        outputManifest.add({
          'type': typeName,
          'url': '$baseUrl/\$export-file/$jobId/$typeName.ndjson',
          'count': count,
        });
      }
    }

    // Mark job as completed
    await dbInterface.updateExportJob(
      jobId,
      status: 'completed',
      outputJson: jsonEncode(outputManifest),
      errorJson: errorManifest.isNotEmpty ? jsonEncode(errorManifest) : null,
      completedAt: DateTime.now().toUtc(),
    );

    FhirantLogging().logInfo(
      'Export job $jobId completed: ${outputManifest.length} file(s)',
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('Export job $jobId failed', e, stackTrace);
    await _failJob(dbInterface, jobId, e.toString());
  }
}

/// Marks a job as failed with an error message.
Future<void> _failJob(
  FhirAntDb dbInterface,
  String jobId,
  String message,
) async {
  await dbInterface.updateExportJob(
    jobId,
    status: 'error',
    errorJson: jsonEncode([
      {
        'resourceType': 'OperationOutcome',
        'issue': [
          {
            'severity': 'error',
            'code': 'exception',
            'diagnostics': message,
          },
        ],
      },
    ]),
    completedAt: DateTime.now().toUtc(),
  );
}

/// Extracts the base URL from a request.
String _baseUrl(Request request) {
  final uri = request.requestedUri;
  return uri.hasPort
      ? '${uri.scheme}://${uri.host}:${uri.port}'
      : '${uri.scheme}://${uri.host}';
}

/// Returns an OperationOutcome response.
Response _operationOutcome(int statusCode, String message) {
  final outcome = fhir.OperationOutcome(
    issue: [
      fhir.OperationOutcomeIssue(
        severity: statusCode >= 500
            ? fhir.IssueSeverity.fatal
            : fhir.IssueSeverity.error,
        code: statusCode == 404
            ? fhir.IssueType.notFound
            : fhir.IssueType.processing,
        diagnostics: message.toFhirString,
      ),
    ],
  );
  return Response(
    statusCode,
    body: outcome.toJsonString(),
    headers: {'Content-Type': 'application/json'},
  );
}
