import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/auth/request_authorization.dart';
import 'package:fhirant_server/src/services/subscription_service.dart';
import 'package:fhirant_server/src/utils/http_headers.dart';
import 'package:fhirant_server/src/utils/json_patch.dart';
import 'package:fhirant_server/src/utils/patient_scope.dart';
import 'package:fhirant_server/src/utils/search_parser.dart';
import 'package:shelf/shelf.dart';

/// Handler for Transaction and Batch operations: POST /
Future<Response> bundleHandler(
  Request request,
  FhirAntDb dbInterface, {
  SubscriptionService? subscriptions,
}) async {
  final subs = subscriptions ?? SubscriptionService(dbInterface);
  try {
    FhirantLogging().logInfo('Processing Bundle request');
    final body = await request.readAsString();
    final bundle = fhir.Bundle.fromJsonString(body);

    if (bundle.type != fhir.BundleType.transaction &&
        bundle.type != fhir.BundleType.batch) {
      return _validationErrorResponse(
        'Bundle type must be "transaction" or "batch"',
      );
    }

    if (bundle.entry == null || bundle.entry!.isEmpty) {
      return _validationErrorResponse('Bundle must contain at least one entry');
    }

    if (bundle.type == fhir.BundleType.transaction) {
      return await _processTransaction(bundle, dbInterface, request, subs);
    } else {
      return await _processBatch(bundle, dbInterface, request, subs);
    }
  } catch (e, stackTrace) {
    FhirantLogging().logError('Error processing Bundle request', e, stackTrace);
    return _errorResponse(
      'Failed to process Bundle',
      e is BundleEntryException ? e.message : 'Internal error',
      statusCode: 400,
    );
  }
}

Future<Response> _processTransaction(
  fhir.Bundle bundle,
  FhirAntDb dbInterface,
  Request request,
  SubscriptionService subscriptions,
) async {
  FhirantLogging().logInfo(
    'Processing Transaction Bundle with ${bundle.entry!.length} entries',
  );
  final baseUrl =
      '${request.requestedUri.scheme}://${request.requestedUri.host}:${request.requestedUri.port}';
  final operations = <_BundleOperation>[];
  final principal = Principal.of(request);

  for (var i = 0; i < bundle.entry!.length; i++) {
    if (bundle.entry![i].request == null) {
      return _validationErrorResponse('Bundle entry $i missing request');
    }
  }

  // Every POST gets its id now, before anything runs, and the urn:uuid map
  // is complete from the start: a reference to a POST later in the Bundle
  // resolves (REVIEW-2026-09-06 row 16; a forward `urn:uuid` used to be
  // stored unresolved), and a client-supplied id on a POST is ignored as
  // http.html's create requires (REVIEW-2026-09-08 row 21).
  final assignedIds = _assignPostIds(bundle.entry!);
  final urnMap = _buildUrnUuidMap(bundle.entry!, assignedIds);

  // R4B http.html "Transaction Processing Rules" (read 2026-09-06): "Process
  // any DELETE interactions", "Process any POST interactions", "Process any
  // PUT or PATCH interactions", "Process any GET or HEAD interactions",
  // "Resolve any conditional references"; "The outcome of processing the
  // transaction SHALL NOT depend on the order of the resources in the
  // transaction." Entries run in that order; the response keeps the
  // Bundle's order ("entries in the response bundle SHALL be in the same
  // order as the entries in the request").
  final order = List<int>.generate(bundle.entry!.length, (i) => i)
    ..sort((a, b) {
      final byMethod = _methodRank(bundle.entry![a].request!.method)
          .compareTo(_methodRank(bundle.entry![b].request!.method));
      return byMethod != 0 ? byMethod : a.compareTo(b);
    });
  final resultByIndex = List<fhir.BundleEntry?>.filled(
    bundle.entry!.length,
    null,
  );
  final operationByIndex = List<_BundleOperation?>.filled(
    bundle.entry!.length,
    null,
  );

  // A FHIR transaction Bundle is all-or-nothing, so it runs inside a database
  // transaction and a failure rolls the whole thing back.
  //
  // This used to be done by hand: apply each entry, and on failure walk back
  // through the ones already applied re-saving their previous state. That is
  // best-effort by construction — the compensating writes can themselves fail,
  // and the log said as much ("Error during rollback of operation N"), leaving
  // a half-applied Bundle that the specification says cannot happen.
  //
  // It is also far cheaper. Each saveResource commits on its own, and one
  // commit per resource measured 71.7ms against 2.2ms inside a shared
  // transaction — a 100-entry Bundle goes from seconds to well under one.
  int? failedIndex;
  Object? failure;
  try {
    await dbInterface.transaction<void>(() async {
      for (final i in order) {
        try {
          final operation = await _processBundleEntry(
            bundle.entry![i],
            dbInterface,
            baseUrl,
            i,
            urnMap,
            subscriptions,
            principal,
            assignedId: assignedIds[i],
          );
          operations.add(operation);
          resultByIndex[i] = operation.resultEntry;
          operationByIndex[i] = operation;
        } catch (e) {
          // Recorded, then rethrown: the throw is what aborts the database
          // transaction, and the record is what builds the response after it
          // has been rolled back.
          failedIndex = i;
          failure = e;
          rethrow;
        }
      }
    });
  } catch (e, stackTrace) {
    final index = failedIndex;
    final cause = failure ?? e;
    FhirantLogging().logError(
      'Transaction failed at entry $index, rolled back',
      cause,
      stackTrace,
    );
    final statusCode = cause is BundleEntryException ? cause.statusCode : 400;
    // Rolled back: no entry changed anything, and every one is recorded as
    // attempted and failed, the failing entry's status on all of them.
    return _errorResponse(
      'Transaction failed at entry $index',
      cause is BundleEntryException ? cause.message : 'Internal error',
      statusCode: statusCode,
      context: {
        'audit_subtype': 'transaction',
        'audit_entries': _auditEntries(
          bundle,
          operationByIndex: List.filled(bundle.entry!.length, null),
          failedStatus: List.filled(bundle.entry!.length, statusCode),
        ),
      },
    );
  }

  // Only now, after the commit. Notifying from inside the transaction would
  // tell a subscriber a resource exists and then roll it back, and a rest-hook
  // POST cannot be recalled.
  await _notify(subscriptions, operations);

  final resultEntries = resultByIndex.whereType<fhir.BundleEntry>().toList();
  final resultBundle = fhir.Bundle(
    type: fhir.BundleType.transactionResponse,
    entry: resultEntries,
  );
  FhirantLogging().logInfo(
    'Transaction completed successfully with ${resultEntries.length} entries',
  );
  return Response.ok(
    resultBundle.toJsonString(),
    headers: {'Content-Type': 'application/json'},
    context: {
      'audit_subtype': 'transaction',
      'audit_entries': _auditEntries(
        bundle,
        operationByIndex: operationByIndex,
        failedStatus: List.filled(bundle.entry!.length, null),
      ),
    },
  );
}

Future<Response> _processBatch(
  fhir.Bundle bundle,
  FhirAntDb dbInterface,
  Request request,
  SubscriptionService subscriptions,
) async {
  FhirantLogging()
      .logInfo('Processing Batch Bundle with ${bundle.entry!.length} entries');
  final baseUrl =
      '${request.requestedUri.scheme}://${request.requestedUri.host}:${request.requestedUri.port}';
  final resultEntries = <fhir.BundleEntry>[];
  final operations = <_BundleOperation>[];
  final operationByIndex = List<_BundleOperation?>.filled(
    bundle.entry!.length,
    null,
  );
  final failedStatus = List<int?>.filled(bundle.entry!.length, null);
  final principal = Principal.of(request);

  // A POST's id is assigned here too, so a client-supplied id is ignored as
  // on the REST path (REVIEW-2026-09-08 row 21). Batch entries are
  // independent, so the urn map is filled as each POST lands.
  final assignedIds = _assignPostIds(bundle.entry!);
  final urnMap = <String, String>{};

  for (var i = 0; i < bundle.entry!.length; i++) {
    final entry = bundle.entry![i];
    if (entry.request == null) {
      failedStatus[i] = 400;
      resultEntries.add(
        fhir.BundleEntry(
          response: fhir.BundleResponse(
            status: '400'.toFhirString,
            outcome: fhir.OperationOutcome(
              issue: [
                fhir.OperationOutcomeIssue(
                  severity: fhir.IssueSeverity.error,
                  code: fhir.IssueType.processing,
                  diagnostics: r'Bundle entry $i missing request'.toFhirString,
                ),
              ],
            ),
          ),
        ),
      );
      continue;
    }

    try {
      final operation = await _processBundleEntry(
        entry,
        dbInterface,
        baseUrl,
        i,
        urnMap,
        subscriptions,
        principal,
        assignedId: assignedIds[i],
      );
      operations.add(operation);
      resultEntries.add(operation.resultEntry);
      operationByIndex[i] = operation;

      // For batch, update urn map after successful POST
      if (operation.method == fhir.HTTPVerb.pOST &&
          operation.createdResource != null) {
        final fullUrl = entry.fullUrl?.toString() ?? '';
        if (fullUrl.startsWith('urn:uuid:')) {
          final resourceType = operation.createdResource!.resourceTypeString;
          final id = operation.createdResource!.id?.toString() ?? '';
          urnMap[fullUrl] = '$resourceType/$id';
        }
      }
    } catch (e, stackTrace) {
      FhirantLogging().logError('Batch entry $i failed', e, stackTrace);
      final statusCode = e is BundleEntryException ? e.statusCode : 400;
      failedStatus[i] = statusCode;
      final diagnostic =
          e is BundleEntryException ? e.message : 'Batch entry $i failed';
      resultEntries.add(
        fhir.BundleEntry(
          response: fhir.BundleResponse(
            status: '$statusCode'.toFhirString,
            outcome: fhir.OperationOutcome(
              issue: [
                fhir.OperationOutcomeIssue(
                  severity: fhir.IssueSeverity.error,
                  code: fhir.IssueType.exception,
                  diagnostics: diagnostic.toFhirString,
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  // A batch entry commits on its own, so by here every successful one is
  // durable and the notifications are safe to send.
  await _notify(subscriptions, operations);

  final resultBundle =
      fhir.Bundle(type: fhir.BundleType.batchResponse, entry: resultEntries);
  FhirantLogging()
      .logInfo('Batch completed with ${resultEntries.length} entries');
  return Response.ok(
    resultBundle.toJsonString(),
    headers: {'Content-Type': 'application/json'},
    context: {
      'audit_subtype': 'batch',
      'audit_entries': _auditEntries(
        bundle,
        operationByIndex: operationByIndex,
        failedStatus: failedStatus,
      ),
    },
  );
}

/// What the audit middleware records for each entry of a Bundle, in the
/// Bundle's order: the entry's method, the record it touched as
/// `[Type]/[id]` (a created resource by its new id; a search or a failed
/// POST by the request url, which names no record), its status, and for a
/// delete the subject of care resolved before the row went. One AuditEvent
/// per entry follows: a transaction touching N patients used to be one
/// `POST /` event with no entity (REVIEW-2026-09-06 finding 15). IHE BALP
/// (profiles.ihe.net/ITI/BALP/content.html, read 2026-09-09) records a
/// pattern per RESTful interaction and, for the disclosure pattern, says
/// "multiple patients would be done as multiple audit entries".
List<Map<String, Object?>> _auditEntries(
  fhir.Bundle bundle, {
  required List<_BundleOperation?> operationByIndex,
  required List<int?> failedStatus,
}) {
  final entries = <Map<String, Object?>>[];
  for (var i = 0; i < bundle.entry!.length; i++) {
    final request = bundle.entry![i].request;
    final op = operationByIndex[i];
    final method = request?.method.valueString ?? 'POST';
    var url = request?.url.valueString ?? '';
    if (op != null && op.resourceId != null) {
      url = '${op.resourceType}/${op.resourceId}';
    }
    final declared = op?.resultEntry.response?.status;
    final status = failedStatus[i] ??
        int.tryParse((declared?.valueString ?? '200').split(' ').first) ??
        200;
    entries.add({
      'method': method,
      'url': url,
      'status': status,
      if (op != null && op.subjectBeforeDelete != null)
        'patient': 'Patient/${op.subjectBeforeDelete}',
    });
  }
  return entries;
}

/// The processing rank of a method in a transaction: DELETE, then POST,
/// then PUT and PATCH, then GET and HEAD (http.html, quoted in
/// `_processTransaction`).
int _methodRank(fhir.HTTPVerb method) => switch (method) {
      fhir.HTTPVerb.dELETE => 0,
      fhir.HTTPVerb.pOST => 1,
      fhir.HTTPVerb.pUT || fhir.HTTPVerb.pATCH => 2,
      _ => 3,
    };

/// A fresh id for every POST entry that carries a resource, by entry index.
/// The id a client put on a POST body is not used: http.html create, "If an
/// id is provided, the server SHALL ignore it."
Map<int, String> _assignPostIds(List<fhir.BundleEntry> entries) {
  final ids = <int, String>{};
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    if (entry.request?.method != fhir.HTTPVerb.pOST) continue;
    final resource = entry.resource;
    if (resource == null) continue;
    ids[i] = resource.newId().id!.valueString!;
  }
  return ids;
}

/// The map of urn:uuid → ResourceType/id for every POST entry, complete
/// before processing starts, from the ids [_assignPostIds] gave them.
Map<String, String> _buildUrnUuidMap(
  List<fhir.BundleEntry> entries,
  Map<int, String> assignedIds,
) {
  final map = <String, String>{};
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final fullUrl = entry.fullUrl?.toString() ?? '';
    if (!fullUrl.startsWith('urn:uuid:')) continue;
    final id = assignedIds[i];
    if (id == null) continue;
    map[fullUrl] = '${entry.resource!.resourceTypeString}/$id';
  }
  return map;
}

/// Recursively resolve urn:uuid references in a JSON map.
Map<String, dynamic> _resolveUrnReferences(
  Map<String, dynamic> json,
  Map<String, String> urnMap,
) {
  final result = <String, dynamic>{};
  for (final entry in json.entries) {
    result[entry.key] = _resolveValue(entry.value, urnMap);
  }
  return result;
}

dynamic _resolveValue(dynamic value, Map<String, String> urnMap) {
  if (value is String) {
    if (value.startsWith('urn:uuid:') && urnMap.containsKey(value)) {
      return urnMap[value];
    }
    return value;
  } else if (value is Map<String, dynamic>) {
    return _resolveUrnReferences(value, urnMap);
  } else if (value is Map) {
    final converted = <String, dynamic>{};
    for (final e in value.entries) {
      converted[e.key.toString()] = _resolveValue(e.value, urnMap);
    }
    return converted;
  } else if (value is List) {
    return value.map((e) => _resolveValue(e, urnMap)).toList();
  }
  return value;
}

/// Refuses the entry when [principal] may not make the same request alone.
///
/// An entry `PUT Patient/p2` is the request `PUT /Patient/p2`: the same
/// scope check ([authorizeRequest]) and, for a token with a patient
/// compartment, the same confinement of what it reads, writes and deletes.
/// Nothing inside a Bundle used to be authorized, so a read-only patient
/// token rewrote another patient through a transaction, and with the root
/// path public no token was needed at all (REVIEW-2026-09-08 rows 1, 2).
void _authorizeEntry(
  Principal? principal,
  fhir.HTTPVerb method,
  String path,
  int entryIndex,
) {
  if (principal == null) return;
  final refused = authorizeRequest(principal, method.toString(), path);
  if (refused != null) {
    throw BundleEntryException(
      refused.statusCode,
      'Bundle entry $entryIndex: not authorized for $method $path',
    );
  }
}

/// The compartment [principal] confines [permission] on [resourceType]
/// to, as a Patient id, or null.
String? _entryPatient(
  Principal? principal,
  String resourceType,
  String permission,
) =>
    principal?.compartmentFor(resourceType, permission)?.id;

/// Throws the entry's 403 unless the stored resource is in the compartment.
Future<void> _requireStoredInCompartment(
  String? patientId,
  String resourceType,
  String resourceId,
  FhirAntDb dbInterface,
  int entryIndex,
) async {
  if (patientId == null) return;
  if (await isInPatientCompartment(
    resourceType,
    resourceId,
    patientId,
    dbInterface,
  )) {
    return;
  }
  throw BundleEntryException(
    403,
    'Bundle entry $entryIndex: $resourceType/$resourceId is not in the '
    'patient compartment for Patient/$patientId',
  );
}

/// Throws the entry's 403 unless the resource about to be written is in
/// the compartment.
Future<void> _requireBodyInCompartment(
  String? patientId,
  fhir.Resource resource,
  int entryIndex,
) async {
  if (patientId == null) return;
  if (await isNewResourceInPatientCompartment(resource, patientId)) return;
  throw BundleEntryException(
    403,
    'Bundle entry $entryIndex: the resource is not in the patient '
    'compartment for Patient/$patientId',
  );
}

Future<_BundleOperation> _processBundleEntry(
  fhir.BundleEntry entry,
  FhirAntDb dbInterface,
  String baseUrl,
  int entryIndex,
  Map<String, String> urnMap,
  SubscriptionService subscriptions,
  Principal? principal, {
  String? assignedId,
}) async {
  final req = entry.request!;
  final method = req.method;
  var url = req.url.toString();

  // Resolve urn:uuid in the request URL
  if (url.startsWith('urn:uuid:') && urnMap.containsKey(url)) {
    url = urnMap[url]!;
  } else {
    // Check if any part of the URL is a urn:uuid
    for (final urn in urnMap.keys) {
      if (url.contains(urn)) {
        url = url.replaceAll(urn, urnMap[urn]!);
      }
    }
  }

  // The entry URL is a relative FHIR URL: `[type]`, `[type]/[id]`, or
  // either with a query (`Patient?family=One`, a search; `Patient?identifier=x`
  // on a DELETE, a conditional delete). It used to be split on `/` alone, so
  // a search URL became the "resource type" `Patient?family=One` and was
  // refused as invalid (REVIEW-2026-09-08 row 24).
  final entryUri = Uri.parse(url);
  final urlParts = entryUri.path.split('/').where((p) => p.isNotEmpty).toList();
  final query = entryUri.queryParametersAll;
  if (urlParts.isEmpty) {
    throw BundleEntryException(
      400,
      'Bundle entry $entryIndex: Invalid URL format',
    );
  }

  final resourceType = urlParts[0];
  final resourceId = urlParts.length > 1 ? urlParts[1] : null;
  final resourceTypeEnum = fhir.R4ResourceType.fromString(resourceType);
  if (resourceTypeEnum == null) {
    throw BundleEntryException(
      400,
      'Bundle entry $entryIndex: Invalid resource type: $resourceType',
    );
  }
  _authorizeEntry(principal, method, entryUri.path, entryIndex);

  fhir.Resource? resultResource;
  fhir.Resource? previousResource;
  fhir.Resource? createdResource;
  fhir.Resource? deletedResource;
  String? subjectBeforeDelete;
  String status;
  String? location;

  switch (method) {
    case fhir.HTTPVerb.gET:
      if (resourceId == null) {
        // A type-level GET is a search, answered as a searchset Bundle
        // inside the entry (http.html batch/transaction: "The response for
        // a search is a Bundle").
        resultResource = await _entrySearch(
          dbInterface,
          resourceTypeEnum,
          query,
          baseUrl,
          principal?.compartmentFor(resourceType, 's'),
          entryIndex,
        );
        status = '200';
        break;
      }
      resultResource =
          await dbInterface.getResource(resourceTypeEnum, resourceId);
      if (resultResource == null) {
        throw BundleEntryException(
          404,
          'Bundle entry $entryIndex: Resource not found',
        );
      }
      await _requireStoredInCompartment(
        _entryPatient(principal, resourceType, 'r'),
        resourceType,
        resourceId,
        dbInterface,
        entryIndex,
      );
      status = '200';

    case fhir.HTTPVerb.pOST:
      if (entry.resource == null) {
        throw BundleEntryException(
          400,
          'Bundle entry $entryIndex: POST requires resource',
        );
      }
      if (entry.resource!.resourceTypeString != resourceType) {
        throw BundleEntryException(
          400,
          'Bundle entry $entryIndex: Resource type mismatch',
        );
      }

      final createPatient = _entryPatient(principal, resourceType, 'c');

      // Conditional create: ifNoneExist
      final ifNoneExist = req.ifNoneExist?.valueString;
      if (ifNoneExist != null && ifNoneExist.isNotEmpty) {
        // queryParametersAll, not splitQueryString: a repeated parameter is
        // an AND (R4 3.1.1.4.17) and splitQueryString keeps only the last.
        final searchMap = Uri(query: ifNoneExist).queryParametersAll;
        final List<fhir.Resource> existing;
        try {
          existing = await dbInterface.search(
            resourceType: resourceTypeEnum,
            searchParameters: searchMap,
            compartment: createPatient == null
                ? null
                : patientCompartment(createPatient),
          );
        } on UnsupportedSearchModifier catch (e) {
          throw BundleEntryException(
            400,
            'Bundle entry $entryIndex: ifNoneExist: ${e.message}',
          );
        } on InvalidSearchValue catch (e) {
          throw BundleEntryException(
            400,
            'Bundle entry $entryIndex: ifNoneExist: ${e.message}',
          );
        } on AmbiguousReference catch (e) {
          throw BundleEntryException(
            400,
            'Bundle entry $entryIndex: ifNoneExist: ${e.message}',
          );
        }
        if (existing.length == 1) {
          // Return existing resource
          resultResource = existing.first;
          status = '200';
          break;
        } else if (existing.length > 1) {
          throw BundleEntryException(
            412,
            'Bundle entry $entryIndex: ifNoneExist matched multiple resources',
          );
        }
        // 0 matches → proceed with create
      }

      // Resolve urn:uuid references in the resource
      var resourceJson = entry.resource!.toJson();
      if (urnMap.isNotEmpty) {
        resourceJson = _resolveUrnReferences(resourceJson, urnMap);
      }
      // The id assigned before processing began; never the client's.
      final withId = fhir.Resource.fromJson(resourceJson);
      final resourceToSave = await _activated(
        assignedId == null
            ? withId.newId()
            : withId.copyWith(id: assignedId.toFhirString),
        subscriptions,
        principal,
        entryIndex,
      );
      await _requireBodyInCompartment(
        createPatient,
        resourceToSave,
        entryIndex,
      );

      final saved = await dbInterface.saveResource(resourceToSave);
      if (saved == null) {
        throw BundleEntryException(
          500,
          'Bundle entry $entryIndex: Failed to create resource',
        );
      }
      resultResource = saved;
      createdResource = resultResource;
      status = '201';
      // http.html create: "Location: [base]/[type]/[id]/_history/[vid]".
      location = '$baseUrl/$resourceType/${resultResource.id}/_history/'
          '${resultResource.meta?.versionId?.valueString ?? '1'}';

      // Update urn map for subsequent entries
      final fullUrl = entry.fullUrl?.toString() ?? '';
      if (fullUrl.startsWith('urn:uuid:') && !urnMap.containsKey(fullUrl)) {
        urnMap[fullUrl] = '$resourceType/${resultResource.id}';
      }

    case fhir.HTTPVerb.pUT:
      if (resourceId == null) {
        throw BundleEntryException(
          400,
          'Bundle entry $entryIndex: PUT requires resource ID',
        );
      }
      if (entry.resource == null) {
        throw BundleEntryException(
          400,
          'Bundle entry $entryIndex: PUT requires resource',
        );
      }
      if (entry.resource!.resourceTypeString != resourceType) {
        throw BundleEntryException(
          400,
          'Bundle entry $entryIndex: Resource type mismatch',
        );
      }
      final resourceIdFromBody = entry.resource!.id?.toString() ?? '';
      if (resourceIdFromBody != resourceId) {
        throw BundleEntryException(
          400,
          'Bundle entry $entryIndex: Resource ID mismatch',
        );
      }

      final updatePatient = _entryPatient(principal, resourceType, 'u');
      if (updatePatient != null &&
          await dbInterface.getResource(resourceTypeEnum, resourceId) != null) {
        await _requireStoredInCompartment(
          updatePatient,
          resourceType,
          resourceId,
          dbInterface,
          entryIndex,
        );
      }

      // Conditional update: ifMatch, checked INSIDE the store's write
      // (`saveResource(ifMatchVersion:)`, the same compare-and-swap as
      // `PUT /[type]/[id]`). It used to compare the raw header string to
      // `W/"n"` outside the write, and a mismatch on a resource that did
      // not exist yet silently created it (REVIEW-2026-09-08 row 22).
      final ifMatchVersion =
          FhirHttpHeaders.parseETag(req.ifMatch?.valueString);
      previousResource =
          await dbInterface.getResource(resourceTypeEnum, resourceId);

      // Resolve urn:uuid references in the resource
      var putJson = entry.resource!.toJson();
      if (urnMap.isNotEmpty) {
        putJson = _resolveUrnReferences(putJson, urnMap);
      }
      final putResource = await _activated(
        fhir.Resource.fromJson(putJson),
        subscriptions,
        principal,
        entryIndex,
      );
      await _requireBodyInCompartment(updatePatient, putResource, entryIndex);

      final fhir.Resource? updated;
      try {
        updated = await dbInterface.saveResource(
          putResource,
          ifMatchVersion: ifMatchVersion,
        );
      } on VersionConflict {
        throw BundleEntryException(
          412,
          'Bundle entry $entryIndex: version mismatch (ifMatch precondition '
          'failed)',
        );
      }
      if (updated == null) {
        throw BundleEntryException(
          500,
          'Bundle entry $entryIndex: Failed to update resource',
        );
      }
      resultResource = updated;
      status = previousResource == null ? '201' : '200';

    case fhir.HTTPVerb.pATCH:
      if (resourceId == null) {
        throw BundleEntryException(
          400,
          'Bundle entry $entryIndex: PATCH requires resource ID',
        );
      }
      if (entry.resource == null) {
        throw BundleEntryException(
          400,
          'Bundle entry $entryIndex: PATCH requires patch document',
        );
      }

      final currentResource =
          await dbInterface.getResource(resourceTypeEnum, resourceId);
      if (currentResource == null) {
        throw BundleEntryException(
          404,
          'Bundle entry $entryIndex: Resource not found for PATCH',
        );
      }
      previousResource = currentResource;
      final patchPatient = _entryPatient(principal, resourceType, 'u');
      await _requireStoredInCompartment(
        patchPatient,
        resourceType,
        resourceId,
        dbInterface,
        entryIndex,
      );

      // Parse patch document from the entry resource
      List<dynamic> patchOperations;
      final patchResource = entry.resource!;
      if (patchResource.resourceTypeString == 'Binary') {
        // Binary: base64-decode the data field to get JSON Patch array
        final patchJson = patchResource.toJson();
        final data = patchJson['data'] as String?;
        if (data == null) {
          throw BundleEntryException(
            400,
            'Bundle entry $entryIndex: Binary patch missing data field',
          );
        }
        final decoded = utf8.decode(base64Decode(data));
        patchOperations = jsonDecode(decoded) as List<dynamic>;
      } else if (patchResource.resourceTypeString == 'Parameters') {
        // FHIRPath Patch is not implemented (REVIEW-2026-09-06 finding 23);
        // the same refusal as PATCH on a resource.
        throw BundleEntryException(
          415,
          'Bundle entry $entryIndex: FHIRPath Patch (a Parameters body) is '
          'not supported; send a JSON Patch document as a Binary',
        );
      } else {
        throw BundleEntryException(
          400,
          'Bundle entry $entryIndex: PATCH document must be a Binary '
          'carrying a JSON Patch document',
        );
      }

      final patchedJson =
          applyJsonPatch(currentResource.toJson(), patchOperations);
      final patchedResource = fhir.Resource.fromJson(patchedJson);

      // Validate type and ID unchanged
      if (patchedResource.resourceTypeString != resourceType) {
        throw BundleEntryException(
          400,
          'Bundle entry $entryIndex: PATCH cannot change resource type',
        );
      }
      final patchedId = patchedResource.id?.toString() ?? '';
      if (patchedId != resourceId) {
        throw BundleEntryException(
          400,
          'Bundle entry $entryIndex: PATCH cannot change resource ID',
        );
      }

      await _requireBodyInCompartment(
        patchPatient,
        patchedResource,
        entryIndex,
      );

      // A patch can change criteria or channel, so the server has to decide
      // again whether it can honour the subscription.
      final patchedToSave = await _activated(
        patchedResource,
        subscriptions,
        principal,
        entryIndex,
      );
      final fhir.Resource? patchSaved;
      try {
        patchSaved = await dbInterface.saveResource(
          patchedToSave,
          ifMatchVersion: FhirHttpHeaders.parseETag(req.ifMatch?.valueString),
        );
      } on VersionConflict {
        throw BundleEntryException(
          412,
          'Bundle entry $entryIndex: version mismatch (ifMatch precondition '
          'failed)',
        );
      }
      if (patchSaved == null) {
        throw BundleEntryException(
          500,
          'Bundle entry $entryIndex: Failed to save patched resource',
        );
      }
      resultResource = patchSaved;
      status = '200';

    case fhir.HTTPVerb.dELETE:
      if (resourceId == null) {
        // A type-level DELETE with a query is the conditional delete,
        // bounded as `DELETE /[type]?…` is.
        final deleted = await _entryConditionalDelete(
          dbInterface,
          resourceTypeEnum,
          query,
          principal?.compartmentFor(resourceType, 'd'),
          entryIndex,
        );
        resultResource = null;
        status = deleted == 0 ? '200' : '204';
        break;
      }

      final existingResource =
          await dbInterface.getResource(resourceTypeEnum, resourceId);
      if (existingResource == null) {
        throw BundleEntryException(
          404,
          'Bundle entry $entryIndex: Resource not found for DELETE',
        );
      }
      deletedResource = existingResource;
      // The audit trail names the subject of care; after the delete the
      // index rows that answer that are gone, so it is read now.
      subjectBeforeDelete = await dbInterface.subjectOfCare(
        resourceType,
        resourceId,
      );
      await _requireStoredInCompartment(
        _entryPatient(principal, resourceType, 'd'),
        resourceType,
        resourceId,
        dbInterface,
        entryIndex,
      );

      final deleteSuccess =
          await dbInterface.deleteResource(resourceTypeEnum, resourceId);
      if (!deleteSuccess) {
        throw BundleEntryException(
          500,
          'Bundle entry $entryIndex: Failed to delete resource',
        );
      }

      resultResource = null;
      status = '204';

    default:
      throw BundleEntryException(
        400,
        'Bundle entry $entryIndex: Unsupported HTTP method: $method',
      );
  }

  // Build response with etag/lastModified for mutating operations
  fhir.FhirString? etag;
  fhir.FhirInstant? lastModified;
  if (resultResource != null && method != fhir.HTTPVerb.gET) {
    etag = FhirHttpHeaders.etag(resultResource).toFhirString;
    lastModified = resultResource.meta?.lastUpdated;
  }

  final resultEntry = fhir.BundleEntry(
    response: fhir.BundleResponse(
      status: status.toFhirString,
      location: location != null ? fhir.FhirUri(location) : null,
      etag: etag,
      lastModified: lastModified,
    ),
    resource: resultResource,
    fullUrl: resultResource != null
        ? fhir.FhirUri('$baseUrl/$resourceType/${resultResource.id}')
        : null,
  );

  return _BundleOperation(
    method: method,
    resourceType: resourceTypeEnum,
    resourceId: resourceId ?? resultResource?.id?.toString(),
    resultEntry: resultEntry,
    previousResource: previousResource,
    createdResource: createdResource,
    deletedResource: deletedResource,
    notifiableResource: method == fhir.HTTPVerb.dELETE ? null : resultResource,
    subjectBeforeDelete: subjectBeforeDelete,
  );
}

/// A type-level GET inside a Bundle: the search, answered as a searchset
/// Bundle with `total` and the page's match entries. The page is `_count`
/// (default 20) and `_offset`; `_sort` is applied; a parameter the store
/// has no definition for is ignored, as on the REST path under lenient
/// handling. Inside [compartment] when the caller's search of the type is
/// confined.
Future<fhir.Bundle> _entrySearch(
  FhirAntDb dbInterface,
  fhir.R4ResourceType type,
  Map<String, List<String>> query,
  String baseUrl,
  CompartmentScope? compartment,
  int entryIndex,
) async {
  final parsed = SearchParameterParser.parseQueryParameters(query);
  final invalid = parsed['invalidParams'] as List<String>?;
  if (invalid != null) {
    throw BundleEntryException(
      400,
      'Bundle entry $entryIndex: ${invalid.join('; ')}',
    );
  }
  final searchParams = parsed['searchParams'] as Map<String, List<String>>?;
  final count = parsed['count'] as int? ?? 20;
  final offset = parsed['offset'] as int? ?? 0;
  final sort = parsed['sort'] as List<String>?;
  try {
    final total = await dbInterface.searchCount(
      resourceType: type,
      searchParameters: searchParams,
      compartment: compartment,
    );
    final page = count == 0
        ? const <fhir.Resource>[]
        : await dbInterface.search(
            resourceType: type,
            searchParameters: searchParams,
            count: count,
            offset: offset,
            sort: sort,
            compartment: compartment,
          );
    return fhir.Bundle(
      type: fhir.BundleType.searchset,
      total: fhir.FhirUnsignedInt(total),
      entry: page.isEmpty
          ? null
          : [
              for (final r in page)
                fhir.BundleEntry(
                  resource: r,
                  fullUrl: fhir.FhirUri(
                    '$baseUrl/${r.resourceTypeString}/${r.id?.valueString}',
                  ),
                  search: const fhir.BundleSearch(
                    mode: fhir.SearchEntryMode.match,
                  ),
                ),
            ],
    );
  } on UnsupportedSearchModifier catch (e) {
    throw BundleEntryException(400, 'Bundle entry $entryIndex: ${e.message}');
  } on InvalidSearchValue catch (e) {
    throw BundleEntryException(400, 'Bundle entry $entryIndex: ${e.message}');
  } on AmbiguousReference catch (e) {
    throw BundleEntryException(400, 'Bundle entry $entryIndex: ${e.message}');
  } on UnsupportedValueSetCompose catch (e) {
    throw BundleEntryException(400, 'Bundle entry $entryIndex: ${e.message}');
  }
}

/// A type-level DELETE inside a Bundle: the conditional delete, bounded at
/// [kMaxConditionalDeletes] matches as `DELETE /[type]?…` is (more is a
/// 412), inside [compartment] when the caller's delete of the type is
/// confined. Returns how many were deleted.
Future<int> _entryConditionalDelete(
  FhirAntDb dbInterface,
  fhir.R4ResourceType type,
  Map<String, List<String>> query,
  CompartmentScope? compartment,
  int entryIndex,
) async {
  final parsed = SearchParameterParser.parseQueryParameters(query);
  final searchParams = parsed['searchParams'] as Map<String, List<String>>?;
  if (searchParams == null || searchParams.isEmpty) {
    throw BundleEntryException(
      400,
      'Bundle entry $entryIndex: a DELETE without an id needs search '
      'criteria (conditional delete)',
    );
  }
  final matches = await dbInterface.search(
    resourceType: type,
    searchParameters: searchParams,
    count: kMaxConditionalDeletes + 1,
    compartment: compartment,
  );
  if (matches.length > kMaxConditionalDeletes) {
    throw BundleEntryException(
      412,
      'Bundle entry $entryIndex: conditional delete matches more than '
      '$kMaxConditionalDeletes resources; narrow the criteria',
    );
  }
  var deleted = 0;
  for (final r in matches) {
    if (await dbInterface.deleteResource(type, r.id!.valueString!)) {
      deleted++;
    }
  }
  return deleted;
}

/// Lets the server decide a `Subscription`'s status before it is stored.
///
/// R4 subscription.html gives the server that call: a client creates one as
/// `requested`, and the server moves it to `active` or `error`. Without this a
/// Bundle was a way to store a subscription the server had never validated,
/// which the single-resource endpoints do not allow. Any other resource passes
/// through untouched.
///
/// The same rule as the REST handlers' `storeRefusal`: a rest-hook
/// Subscription is system authority's to create or change.
Future<fhir.Resource> _activated(
  fhir.Resource resource,
  SubscriptionService subscriptions,
  Principal? principal,
  int entryIndex,
) async {
  final refused = storeRefusal(principal, resource);
  if (refused != null) {
    throw BundleEntryException(
      403,
      'Bundle entry $entryIndex: a rest-hook Subscription requires '
      'system-level (admin) privilege',
    );
  }
  return resource is fhir.Subscription
      ? await subscriptions.activate(resource)
      : resource;
}

/// Sends notifications for the writes a Bundle made, once they are durable.
///
Future<void> _notify(
  SubscriptionService subscriptions,
  List<_BundleOperation> operations,
) async {
  for (final operation in operations) {
    final resource = operation.notifiableResource;
    if (resource != null) {
      await subscriptions.onResourceChanged(resource);
    }
  }
}

class _BundleOperation {
  _BundleOperation({
    required this.method,
    required this.resourceType,
    required this.resourceId,
    required this.resultEntry,
    this.previousResource,
    this.createdResource,
    this.deletedResource,
    this.notifiableResource,
    this.subjectBeforeDelete,
  });
  final fhir.HTTPVerb method;
  final fhir.R4ResourceType resourceType;
  final String? resourceId;
  final fhir.BundleEntry resultEntry;
  final fhir.Resource? previousResource;
  final fhir.Resource? createdResource;
  final fhir.Resource? deletedResource;

  /// The resource as saved, for a create or an update, and null for a delete.
  ///
  /// R4 subscription.html: "there is no notification when a resource is
  /// deleted", so a delete deliberately leaves this null and nothing is sent.
  final fhir.Resource? notifiableResource;

  /// For a delete, the Patient id the deleted resource belonged to, read
  /// before the delete so the audit record can still name the subject.
  final String? subjectBeforeDelete;
}

/// Exception for bundle entry processing that carries an HTTP status code.
class BundleEntryException implements Exception {
  BundleEntryException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

Response _errorResponse(
  String message,
  String details, {
  int statusCode = 500,
  Map<String, Object>? context,
}) {
  final operationOutcome = fhir.OperationOutcome(
    issue: [
      fhir.OperationOutcomeIssue(
        severity: fhir.IssueSeverity.error,
        code: fhir.IssueType.exception,
        diagnostics: '$message: $details'.toFhirString,
      ),
    ],
  );
  FhirantLogging().logWarning('Error Response: $message - $details');
  return Response(
    statusCode,
    body: operationOutcome.toJsonString(),
    headers: {'Content-Type': 'application/json'},
    context: context,
  );
}

Response _validationErrorResponse(String message) {
  final operationOutcome = fhir.OperationOutcome(
    issue: [
      fhir.OperationOutcomeIssue(
        severity: fhir.IssueSeverity.error,
        code: fhir.IssueType.processing,
        diagnostics: message.toFhirString,
      ),
    ],
  );
  FhirantLogging().logWarning('Validation Error: $message');
  return Response(
    400,
    body: operationOutcome.toJsonString(),
    headers: {'Content-Type': 'application/json'},
  );
}
