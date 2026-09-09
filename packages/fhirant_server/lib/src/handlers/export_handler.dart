import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhir_r4_bulk/fhir_r4_bulk.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/auth/request_authorization.dart';
import 'package:fhirant_server/src/utils/spec_loader.dart' show specTag;
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

/// Export job ids are UUIDs (see [exportKickoffHandler]). Anything else in a
/// `jobId` path segment is rejected so it can never traverse the export dir.
final _jobIdPattern = RegExp(
  '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

bool _isValidJobId(String jobId) => _jobIdPattern.hasMatch(jobId);

/// The file items stored on a job (`outputJson`/`errorJson`), as the
/// manifest's items.
List<BulkExportFile> _files(String? json) => json == null
    ? const []
    : [
        for (final item in jsonDecode(json) as List<dynamic>)
          BulkExportFile.fromJson(item as Map<String, dynamic>),
      ];

/// The OperationOutcome a failed job answers its status request with: the
/// issues of every OperationOutcome stored on the job (`_failJob`,
/// `FhirAntDb.failStaleExportJobs`), or one saying only that it failed.
Map<String, dynamic> _failureOutcome(String? errorJson) {
  final issues = <dynamic>[
    if (errorJson != null)
      for (final outcome in jsonDecode(errorJson) as List<dynamic>)
        ...?(outcome as Map<String, dynamic>)['issue'] as List<dynamic>?,
  ];
  return {
    'resourceType': 'OperationOutcome',
    'issue': issues.isNotEmpty
        ? issues
        : [
            {
              'severity': 'error',
              'code': 'exception',
              'diagnostics': 'The export failed',
            },
          ],
  };
}

/// Writes [lines] to an NDJSON file at [filePath] as they arrive
/// (`NdjsonStream.write`, flushed every 500 lines so the file, not the
/// heap, holds the output) and returns how many were written.
Future<int> _writeNdjsonFile(String filePath, Stream<String> lines) async {
  final file = File(filePath);
  await file.parent.create(recursive: true);
  final sink = file.openWrite();
  try {
    return await NdjsonStream.write(lines, sink, flush: sink.flush);
  } finally {
    await sink.close();
  }
}

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

    // 2. The kick-off parameters (fhir_r4_bulk's BulkExportKickoff): a
    // repeated `_type` and a comma-delimited one are the same list, which
    // export.html requires and `queryParameters['_type']` (the last value
    // only) did not give; `_since` and `_typeFilter` are checked as parsed.
    final BulkExportKickoff kickoff;
    try {
      kickoff = BulkExportKickoff.fromQuery(request.url.queryParametersAll);
    } on FormatException catch (e) {
      return _operationOutcome(400, e.message);
    }
    if (!kickoff.outputFormatSupported) {
      return _operationOutcome(
        400,
        'Unsupported _outputFormat: ${kickoff.outputFormat}. '
        'Supported formats: ${bulkOutputFormats.join(', ')}',
      );
    }
    // Bulk Data 2.0.0 export.html "Query Parameters" (read 2026-09-08): "A
    // server that is unable to support _elements SHOULD return an error and
    // FHIR OperationOutcome resource so the client can re-submit a request
    // omitting the _elements parameter. When a Prefer: handling=lenient
    // header is included in the request, the server MAY process the request
    // instead of returning an error." The same sentence stands for `patient`
    // and `includeAssociatedData`. These used to be parsed and ignored, so
    // `?patient=Patient/p1` ran a full export (REVIEW-2026-09-08 row 29).
    final unsupported = <String>[
      if (kickoff.elements.isNotEmpty) '_elements',
      if (kickoff.patients.isNotEmpty) 'patient',
      if (kickoff.includeAssociatedData.isNotEmpty) 'includeAssociatedData',
    ];
    final prefersLenient =
        (request.headers['prefer'] ?? '').contains('handling=lenient');
    if (unsupported.isNotEmpty && !prefersLenient) {
      return _operationOutcome(
        400,
        'This server does not support ${unsupported.join(', ')}; omit the '
        'parameter, or send Prefer: handling=lenient to have it ignored.',
      );
    }
    for (final filter in kickoff.typeFilters) {
      if (!filter.resourceTypeKnown) {
        return _operationOutcome(
          400,
          'Invalid resource type in _typeFilter: ${filter.resourceType}',
        );
      }
    }
    final typeParam = kickoff.types.isEmpty ? null : kickoff.types.join(',');
    final since = kickoff.since;
    final typeFilterParams = [
      for (final filter in kickoff.typeFilters) filter.toString(),
    ];

    // 3. The caller must be able to read every type the job will write.
    // The middleware checked the FIRST path segment only, so `user/Group.r`
    // alone started `Group/[id]/$export` and the worker wrote every
    // Patient-compartment type to disk (REVIEW-2026-09-08 row 12); the
    // system-level export is admin/system-scoped in the middleware. A
    // caller with a patient compartment on any of the types is refused:
    // the export is not confined to a compartment.
    final principal = Principal.of(request);
    if (principal != null && exportLevel != 'system') {
      final compartmentTypes = <String>{
        'Patient',
        ...compartmentDefinitions['Patient']!.keys,
      };
      final wanted = kickoff.types.isEmpty
          ? compartmentTypes
          : compartmentTypes.intersection(kickoff.types.toSet());
      final unreadable = principal.unauthorizedTypes(wanted, 'r');
      if (unreadable.isNotEmpty) {
        return forbidden(
          'Insufficient scope to export ${unreadable.join(', ')}; narrow '
          'the request with _type or obtain a scope covering them.',
        );
      }
      final confined =
          wanted.where((t) => principal.compartmentFor(t, 'r') != null);
      if (confined.isNotEmpty) {
        return forbidden(
          'A patient-scoped token cannot run a bulk export: the export is '
          'not confined to the patient compartment.',
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
      // The owner: the status, file and cancel routes are answered to this
      // account and to system authority, and to nobody else.
      requestedBy: principal?.userId.toString(),
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

/// A 403 unless the caller is the account that kicked [job] off or holds
/// system authority (admin role or a `system/` scope), or null. The three
/// job routes used to be admin-only, so a clinician who started
/// `Patient/$export` could never collect it (REVIEW-2026-09-08 row 12).
Response? _refuseUnlessOwner(Request request, ExportJob job) {
  final principal = Principal.of(request);
  if (principal == null || principal.isSystem) return null;
  if (job.requestedBy == principal.userId.toString()) return null;
  return forbidden('This export job belongs to another account.');
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
    final refused = _refuseUnlessOwner(request, job);
    if (refused != null) return refused;

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
        final manifest = BulkExportManifest(
          transactionTime: job.transactionTime,
          request: job.requestUrl,
          requiresAccessToken: true,
          output: _files(job.outputJson),
          error: _files(job.errorJson),
        ).toJson();
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
        // Bulk Data v2.0.0 export.html, section "Bulk Data Status Request",
        // read whole 2026-09-08, verbatim: "In the case that errors prevent
        // the export from completing, the server SHOULD respond with a FHIR
        // OperationOutcome resource in JSON format." and, under "Response -
        // Error Status", verbatim: "Content-Type header of
        // application/fhir+json when body is a FHIR OperationOutcome
        // resource". This used to answer with a manifest whose `error`
        // array held the OperationOutcomes inline, which is neither the
        // error body nor the manifest's file-item shape.
        return Response(
          500,
          body: jsonEncode(_failureOutcome(job.errorJson)),
          headers: {'Content-Type': 'application/fhir+json'},
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
  FhirAntDb dbInterface,
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
    final job = await dbInterface.getExportJob(jobId);
    if (job == null) {
      return _operationOutcome(404, 'Export job not found: $jobId');
    }
    final refused = _refuseUnlessOwner(request, job);
    if (refused != null) return refused;

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
    final refused = _refuseUnlessOwner(request, job);
    if (refused != null) return refused;

    // Mark as cancelled. A job that is still running keeps its row: the
    // worker sees `cancelled` at its next check, stops, and removes its own
    // directory, and the hourly sweep removes the row after the retention
    // period. Deleting the row and the directory here while the worker was
    // writing left files nobody owned until the sweep (REVIEW-2026-09-08
    // row 39). A finished job is removed at once.
    final running = job.status == 'pending' || job.status == 'in_progress';
    await dbInterface.updateExportJob(
      jobId,
      status: 'cancelled',
      completedAt: DateTime.now().toUtc(),
    );
    final jobDir = Directory('$exportDir/$jobId');
    if (!running) {
      if (jobDir.existsSync()) {
        await jobDir.delete(recursive: true);
      }
      await dbInterface.deleteExportJob(jobId);
    }

    FhirantLogging().logInfo('Export job $jobId cancelled and cleaned up');

    return Response(202, body: '');
  } catch (e, stackTrace) {
    FhirantLogging().logError('Error deleting export job', e, stackTrace);
    return _operationOutcome(500, 'Internal error');
  }
}

/// Removes a job's output directory, if it exists; the worker's own
/// clean-up when it finds the job cancelled.
Future<void> _removeJobDir(String exportDir, String jobId) async {
  final dir = Directory('$exportDir/$jobId');
  if (dir.existsSync()) await dir.delete(recursive: true);
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
    if (job == null || job.status == 'cancelled') {
      await _removeJobDir(exportDir, jobId);
      return;
    }

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

    // Patient-level: the members of the Patient compartments, by type.
    // Bulk Data export.html, patient-level: "Obtain a detailed set of FHIR
    // resources of diverse resource types pertaining to all patients". A
    // resource of a compartment type with no patient (an Observation with
    // no subject) is not about a patient; every resource of the type used
    // to be written (REVIEW-2026-09-08 row 40).
    final patientLevel = job.exportLevel == 'patient';
    if (patientLevel) {
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
        if (currentJob == null || currentJob.status == 'cancelled') {
          await _removeJobDir(exportDir, jobId);
          return;
        }

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
        if (currentJob == null || currentJob.status == 'cancelled') {
          await _removeJobDir(exportDir, jobId);
          return;
        }

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
        final count = await _writeNdjsonFile(
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
      if (currentJob == null || currentJob.status == 'cancelled') {
        await _removeJobDir(exportDir, jobId);
        return;
      }

      final typeName = resourceType.toString();

      // Check for matching _typeFilter entries
      final matchingFilters =
          typeFilters?.where((f) => f.startsWith('$typeName?')).toList() ?? [];

      // The stored JSON is streamed to the file a page at a time
      // (FhirAntDb.exportJson); a _typeFilter picks the ids first, each
      // filter one search, united (OR), and `_since` is applied in SQL.
      // Patient-level, member type: the ids in some Patient's compartment.
      // Every Patient is in its own compartment, so the Patient type itself
      // is not narrowed.
      Set<String>? memberIds;
      if (patientLevel && typeName != 'Patient') {
        memberIds = await dbInterface.compartmentTypeMembers(
          'Patient',
          typeName,
          since: since,
        );
        if (memberIds.isEmpty) continue;
      }

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
          ids: memberIds == null ? ids : ids.where(memberIds.contains),
          withoutTag: withoutTag,
        );
      } else {
        lines = dbInterface.exportJson(
          resourceType,
          since: since,
          ids: memberIds,
          withoutTag: withoutTag,
        );
      }

      final path = '$exportDir/$jobId/$typeName.ndjson';
      final count = await _writeNdjsonFile(path, lines);
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
