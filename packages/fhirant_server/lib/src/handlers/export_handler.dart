import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/utils/ndjson_writer.dart';
import 'package:fhirant_server/src/utils/spec_loader.dart' show specTag;
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

const _validFormats = [
  'application/fhir+ndjson',
  'application/ndjson',
  'ndjson',
];

/// Export job ids are UUIDs (see [exportKickoffHandler]). Anything else in a
/// `jobId` path segment is rejected so it can never traverse the export dir.
final _jobIdPattern = RegExp(
  '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

bool _isValidJobId(String jobId) => _jobIdPattern.hasMatch(jobId);

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

    // 4b. Parse _typeFilter (may appear multiple times)
    final typeFilterParams =
        request.url.queryParametersAll['_typeFilter'] ?? [];
    for (final filter in typeFilterParams) {
      if (!filter.contains('?')) {
        return _operationOutcome(
          400,
          'Invalid _typeFilter: $filter. '
          'Expected format: ResourceType?searchParams',
        );
      }
      final typeName = filter.split('?')[0];
      if (fhir.R4ResourceType.fromString(typeName) == null) {
        return _operationOutcome(
          400,
          'Invalid resource type in _typeFilter: $typeName',
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

    await dbInterface.createExportJob(
      jobId: jobId,
      status: 'pending',
      requestUrl: requestUrl,
      transactionTime: transactionTime,
      resourceTypes: typeParam,
      since: since,
      exportLevel: exportLevel,
      patientId: patientId,
      groupId: groupId,
      typeFilters:
          typeFilterParams.isNotEmpty ? jsonEncode(typeFilterParams) : null,
    );

    // 7. Spawn background processing (fire-and-forget)
    unawaited(
      _processExport(dbInterface, jobId, exportDir, request)
          .catchError((Object e, StackTrace st) {
        FhirantLogging().logError('Export job $jobId failed', e, st);
      }),
    );

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
    return _operationOutcome(500, 'Internal error');
  }
}

/// Handler for `GET /$export-poll-status/<jobId>`.
///
/// Returns 202 while in-progress, 200 with manifest when complete,
/// 500 with error details on failure, or 404 if not found.
Future<Response> exportStatusHandler(
  Request request,
  FhirAntDb dbInterface,
  String jobId, {
  Duration retention = kExportRetention,
}) async {
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
        // Bulk Data v2.0.0 export.html "Response - Complete Status", read
        // 2026-09-08: "The server SHOULD return an Expires header indicating
        // when the files listed will no longer be available for access."
        // The files go when the sweep runs after `completedAt + retention`;
        // this used to name the completion time itself, a date already past.
        final expires = job.completedAt?.add(retention);
        return Response.ok(
          jsonEncode(manifest),
          headers: {
            'Content-Type': 'application/json',
            if (expires != null) 'Expires': HttpDate.format(expires.toUtc()),
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
    return _operationOutcome(500, 'Internal error');
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
    // Validate both path segments to prevent traversal out of the export dir.
    if (!_isValidJobId(jobId)) {
      return _operationOutcome(400, 'Invalid job id');
    }
    if (fileName.contains('..') || fileName.contains('/')) {
      return _operationOutcome(400, 'Invalid file name');
    }

    final filePath = '$exportDir/$jobId/$fileName';
    final file = File(filePath);
    if (!file.existsSync()) {
      return _operationOutcome(404, 'Export file not found: $fileName');
    }

    // Streamed from disk with its length: the file used to be read into one
    // String per download (REVIEW-2026-09-06 finding 34).
    final length = await file.length();
    return Response.ok(
      file.openRead(),
      headers: {
        'Content-Type': 'application/fhir+ndjson',
        'Content-Length': '$length',
      },
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('Error serving export file', e, stackTrace);
    return _operationOutcome(500, 'Internal error');
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
    // Defence in depth: this handler deletes a directory built from jobId.
    // The DB lookup below already gates on a real job, but reject a malformed
    // id outright so the path can never traverse the export dir.
    if (!_isValidJobId(jobId)) {
      return _operationOutcome(400, 'Invalid job id');
    }
    final job = await dbInterface.getExportJob(jobId);
    if (job == null) {
      return _operationOutcome(404, 'Export job not found: $jobId');
    }

    // Mark as cancelled (the background worker checks this)
    await dbInterface.updateExportJob(jobId, status: 'cancelled');

    // Delete output files if they exist
    final jobDir = Directory('$exportDir/$jobId');
    if (jobDir.existsSync()) {
      await jobDir.delete(recursive: true);
    }

    // Remove the job row
    await dbInterface.deleteExportJob(jobId);

    FhirantLogging().logInfo('Export job $jobId cancelled and cleaned up');

    return Response(202, body: '');
  } catch (e, stackTrace) {
    FhirantLogging().logError('Error deleting export job', e, stackTrace);
    return _operationOutcome(500, 'Internal error');
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

    // Parse typeFilters from job
    List<String>? typeFilters;
    if (job.typeFilters != null) {
      typeFilters = (jsonDecode(job.typeFilters!) as List).cast<String>();
    }

    // Determine resource types to export
    List<fhir.R4ResourceType> typesToExport;
    if (job.resourceTypes != null && job.resourceTypes!.isNotEmpty) {
      typesToExport = job.resourceTypes!
          .split(',')
          .map((s) => s.trim())
          .map(fhir.R4ResourceType.fromString)
          .whereType<fhir.R4ResourceType>()
          .toList();
    } else {
      typesToExport = await dbInterface.getResourceTypes();
    }

    final outputManifest = <Map<String, dynamic>>[];
    final errorManifest = <Map<String, dynamic>>[];

    if (job.exportLevel == 'patient') {
      // Patient-level export: restrict to Patient compartment resource types
      // (the published CompartmentDefinition, generated into fhir_r4_db, plus
      // the Patient itself).
      final compartmentTypes = {
        'Patient',
        ...compartmentDefinitions['Patient']!.keys,
      };
      if (job.resourceTypes != null && job.resourceTypes!.isNotEmpty) {
        typesToExport = typesToExport
            .where((t) => compartmentTypes.contains(t.toString()))
            .toList();
      } else {
        typesToExport = compartmentTypes
            .map(fhir.R4ResourceType.fromString)
            .whereType<fhir.R4ResourceType>()
            .toList();
        // Only export types that actually exist in the DB
        final existingTypes = await dbInterface.getResourceTypes();
        final existingSet = existingTypes.toSet();
        typesToExport = typesToExport.where(existingSet.contains).toList();
      }
    }

    if (job.exportLevel == 'group') {
      // Group-level export: export Patient compartment resources for
      // group members

      // Fetch the Group resource
      final groupResource = job.groupId != null
          ? await dbInterface.getResource(
              fhir.R4ResourceType.FhirGroup,
              job.groupId!,
            )
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
          'Export job $jobId completed: 0 file(s) '
          '(group has no patient members)',
        );
        return;
      }

      // Determine resource types to export (Patient compartment ∩ _type filter)
      final compartmentTypes = {
        'Patient',
        ...compartmentDefinitions['Patient']!.keys,
      };
      final typeFilter = <String>[];
      if (job.resourceTypes != null && job.resourceTypes!.isNotEmpty) {
        typeFilter
          ..addAll(job.resourceTypes!.split(',').map((s) => s.trim()))
          // Only keep types that are in the Patient compartment
          ..retainWhere(compartmentTypes.contains);
      }

      // Aggregate resource IDs across all patient members
      final allResourceIds = <String, Set<String>>{};
      for (final patientId in patientIds) {
        // Check for cancellation
        final currentJob = await dbInterface.getExportJob(jobId);
        if (currentJob == null || currentJob.status == 'cancelled') return;

        final compartmentIds = await dbInterface.compartmentMembers(
          CompartmentScope('Patient', patientId),
          types: typeFilter.isNotEmpty ? typeFilter : null,
          since: since,
        );

        for (final entry in compartmentIds.entries) {
          allResourceIds.putIfAbsent(entry.key, () => {}).addAll(entry.value);
        }
      }

      // Always include Patient resources for the group members
      final shouldIncludePatient =
          typeFilter.isEmpty || typeFilter.contains('Patient');
      if (shouldIncludePatient) {
        allResourceIds
            .putIfAbsent('Patient', () => {})
            .addAll(patientIds.toSet());
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

        // Check for matching _typeFilter entries
        final matchingFilters =
            typeFilters?.where((f) => f.startsWith('$typeName?')).toList() ??
                [];

        // If typeFilters exist for this type, intersect compartment IDs
        // with search results
        Set<String>? filterIds;
        if (matchingFilters.isNotEmpty) {
          filterIds = {};
          for (final filter in matchingFilters) {
            final queryString = filter.substring(filter.indexOf('?') + 1);
            // queryParametersAll: a repeated parameter is an AND (R4
            // 3.1.1.4.17) and splitQueryString keeps only the last value.
            final searchMap = Uri(query: queryString).queryParametersAll;
            final results = await dbInterface.search(
              resourceType: resourceType,
              searchParameters: searchMap,
            );
            for (final r in results) {
              final rid = r.id?.toString() ?? '';
              if (rid.isNotEmpty) filterIds.add(rid);
            }
          }
        }

        // The compartment's ids (those the filter kept), streamed from the
        // store in chunks; `_since` applies in SQL, which also covers the
        // Patient resources added above without a `since` on their lookup.
        final wanted =
            filterIds == null ? ids : ids.where(filterIds.contains).toSet();
        final path = '$exportDir/$jobId/$typeName.ndjson';
        final count = await writeNdjsonFile(
          path,
          dbInterface.exportJson(resourceType, since: since, ids: wanted),
        );
        if (count == 0) {
          await File(path).delete();
          continue;
        }
        outputManifest.add({
          'type': typeName,
          'url': '$baseUrl/\$export-file/$jobId/$typeName.ndjson',
          'count': count,
        });
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

    // With no `_type`, the export is the deployment's data: the
    // specification load's tagged conformance resources are left out.
    // Naming a type includes them, which is how the terminology comes out.
    // Bulk Data v2.0.0 export.html, read 2026-09-08, on the system-level
    // export: it "supports use cases like backing up a server, or exporting
    // terminology data by restricting the resources returned using the
    // _type parameter".
    final withoutTag = job.resourceTypes == null || job.resourceTypes!.isEmpty
        ? specTag
        : null;

    // Export resources (works for both system and patient level)
    for (final resourceType in typesToExport) {
      // Check for cancellation
      final currentJob = await dbInterface.getExportJob(jobId);
      if (currentJob == null || currentJob.status == 'cancelled') return;

      final typeName = resourceType.toString();

      // Check for matching _typeFilter entries
      final matchingFilters =
          typeFilters?.where((f) => f.startsWith('$typeName?')).toList() ?? [];

      // The stored JSON is streamed to the file a page at a time
      // (FhirAntDb.exportJson); a _typeFilter picks the ids first, each
      // filter one search, united (OR), and `_since` is applied in SQL.
      Stream<String> lines;
      if (matchingFilters.isNotEmpty) {
        final ids = <String>{};
        for (final filter in matchingFilters) {
          final queryString = filter.substring(filter.indexOf('?') + 1);
          final searchMap = Uri(query: queryString).queryParametersAll;
          final results = await dbInterface.search(
            resourceType: resourceType,
            searchParameters: searchMap,
          );
          for (final r in results) {
            final id = r.id?.toString() ?? '';
            if (id.isNotEmpty) ids.add(id);
          }
        }
        lines = dbInterface.exportJson(
          resourceType,
          since: since,
          ids: ids,
          withoutTag: withoutTag,
        );
      } else {
        lines = dbInterface.exportJson(
          resourceType,
          since: since,
          withoutTag: withoutTag,
        );
      }

      final path = '$exportDir/$jobId/$typeName.ndjson';
      final count = await writeNdjsonFile(path, lines);
      if (count == 0) {
        // Bulk Data v2.0.0 export.html, read 2026-09-08: "If no data are
        // found for a resource, the server SHOULD NOT return an output item
        // for that resource in the response."
        await File(path).delete();
        continue;
      }
      outputManifest.add({
        'type': typeName,
        'url': '$baseUrl/\$export-file/$jobId/$typeName.ndjson',
        'count': count,
      });
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
    try {
      await _failJob(dbInterface, jobId, 'Export failed');
    } catch (inner, innerStack) {
      // If marking the failure ALSO fails — the database closed under it, the
      // row deleted — the job would otherwise stay `in_progress` for ever and
      // every poll would answer 202 until the client gave up. Nothing more can
      // be written at this point, so say so where it can be read.
      FhirantLogging().logError(
        'Export job $jobId could not be marked failed; it will stay '
        'in_progress until it is cleaned up',
        inner,
        innerStack,
      );
    }
  }
}

/// How long a finished export's files stay after it completes, when the
/// server is not told otherwise. A day is a choice, not a measurement: long
/// enough to download after an overnight run, short enough that a phone is
/// not carrying last month's exports.
const kExportRetention = Duration(hours: 24);

/// Deletes the files and the row of every finished job older than
/// [retention], and any directory under [exportDir] that no job owns (left by
/// a crash mid-export). Returns how many jobs were removed.
///
/// Bulk Data v2.0.0 export.html, read 2026-09-08: "removal of the file from
/// the server is left up to the server implementer" and "A server SHOULD NOT
/// delete files from a Bulk Data response that a client is actively in the
/// process of downloading regardless of the pre-specified expiration time."
/// A download in progress holds the file open, and unlinking an open file on
/// Linux and Android leaves its data readable until it is closed, so a
/// stream already started completes.
Future<int> sweepExpiredExports(
  FhirAntDb dbInterface,
  String exportDir, {
  Duration retention = kExportRetention,
  DateTime? now,
}) async {
  final cutoff = (now ?? DateTime.now()).subtract(retention);
  final expired = await dbInterface.finishedExportJobsBefore(cutoff);
  for (final job in expired) {
    final dir = Directory('$exportDir/${job.jobId}');
    if (dir.existsSync()) await dir.delete(recursive: true);
    await dbInterface.deleteExportJob(job.jobId);
  }
  final root = Directory(exportDir);
  if (root.existsSync()) {
    final owned = await dbInterface.exportJobIds();
    await for (final entry in root.list()) {
      final name = entry.uri.pathSegments
          .lastWhere((s) => s.isNotEmpty, orElse: () => '');
      if (entry is Directory && _isValidJobId(name) && !owned.contains(name)) {
        await entry.delete(recursive: true);
      }
    }
  }
  if (expired.isNotEmpty) {
    FhirantLogging().logInfo(
      'Export sweep removed ${expired.length} job(s) older than $retention',
    );
  }
  return expired.length;
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
