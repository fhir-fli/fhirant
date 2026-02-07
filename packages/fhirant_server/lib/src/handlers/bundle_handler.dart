import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/utils/http_headers.dart';
import 'package:fhirant_server/src/utils/json_patch.dart';
import 'package:shelf/shelf.dart';

/// Handler for Transaction and Batch operations: POST /
Future<Response> bundleHandler(
  Request request,
  FhirAntDb dbInterface,
) async {
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
      return await _processTransaction(bundle, dbInterface, request);
    } else {
      return await _processBatch(bundle, dbInterface, request);
    }
  } catch (e, stackTrace) {
    FhirantLogging()
        .logError('Error processing Bundle request', e, stackTrace);
    return _errorResponse('Failed to process Bundle', e.toString(),
        statusCode: 400);
  }
}

Future<Response> _processTransaction(
  fhir.Bundle bundle,
  FhirAntDb dbInterface,
  Request request,
) async {
  FhirantLogging().logInfo(
      'Processing Transaction Bundle with ${bundle.entry!.length} entries');
  final baseUrl =
      '${request.requestedUri.scheme}://${request.requestedUri.host}:${request.requestedUri.port}';
  final resultEntries = <fhir.BundleEntry>[];
  final operations = <_BundleOperation>[];

  // Build urn:uuid map for cross-reference resolution
  final urnMap = _buildUrnUuidMap(bundle.entry!);

  for (var i = 0; i < bundle.entry!.length; i++) {
    final entry = bundle.entry![i];
    if (entry.request == null) {
      return _validationErrorResponse('Bundle entry $i missing request');
    }

    try {
      final operation = await _processBundleEntry(
          entry, dbInterface, baseUrl, i, urnMap);
      operations.add(operation);
      resultEntries.add(operation.resultEntry);
    } catch (e, stackTrace) {
      FhirantLogging().logError(
          'Transaction failed at entry $i, rolling back', e, stackTrace);
      for (var j = operations.length - 1; j >= 0; j--) {
        try {
          await _rollbackOperation(operations[j], dbInterface);
        } catch (rollbackError) {
          FhirantLogging()
              .logError('Error during rollback of operation $j', rollbackError);
        }
      }
      return _errorResponse(
          'Transaction failed at entry $i', e.toString(),
          statusCode: 400);
    }
  }

  final resultBundle = fhir.Bundle(
      type: fhir.BundleType.transactionResponse, entry: resultEntries);
  FhirantLogging().logInfo(
      'Transaction completed successfully with ${resultEntries.length} entries');
  return Response.ok(resultBundle.toJsonString(),
      headers: {'Content-Type': 'application/json'});
}

Future<Response> _processBatch(
  fhir.Bundle bundle,
  FhirAntDb dbInterface,
  Request request,
) async {
  FhirantLogging().logInfo(
      'Processing Batch Bundle with ${bundle.entry!.length} entries');
  final baseUrl =
      '${request.requestedUri.scheme}://${request.requestedUri.host}:${request.requestedUri.port}';
  final resultEntries = <fhir.BundleEntry>[];

  // Build urn:uuid map incrementally for batch
  final urnMap = <String, String>{};

  for (var i = 0; i < bundle.entry!.length; i++) {
    final entry = bundle.entry![i];
    if (entry.request == null) {
      resultEntries.add(fhir.BundleEntry(
        response: fhir.BundleResponse(
          status: '400'.toFhirString,
          outcome: fhir.OperationOutcome(issue: [
            fhir.OperationOutcomeIssue(
              severity: fhir.IssueSeverity.error,
              code: fhir.IssueType.processing,
              diagnostics: 'Bundle entry \$i missing request'.toFhirString,
            ),
          ]),
        ),
      ));
      continue;
    }

    try {
      final operation = await _processBundleEntry(
          entry, dbInterface, baseUrl, i, urnMap);
      resultEntries.add(operation.resultEntry);

      // For batch, update urn map after successful POST
      if (operation.method == fhir.HTTPVerb.pOST &&
          operation.createdResource != null) {
        final fullUrl = entry.fullUrl?.toString() ?? '';
        if (fullUrl.startsWith('urn:uuid:')) {
          final resourceType =
              operation.createdResource!.resourceTypeString;
          final id = operation.createdResource!.id?.toString() ?? '';
          urnMap[fullUrl] = '$resourceType/$id';
        }
      }
    } catch (e, stackTrace) {
      FhirantLogging().logError('Batch entry $i failed', e, stackTrace);
      resultEntries.add(fhir.BundleEntry(
        response: fhir.BundleResponse(
          status: '400'.toFhirString,
          outcome: fhir.OperationOutcome(issue: [
            fhir.OperationOutcomeIssue(
              severity: fhir.IssueSeverity.error,
              code: fhir.IssueType.exception,
              diagnostics: e.toString().toFhirString,
            ),
          ]),
        ),
      ));
    }
  }

  final resultBundle = fhir.Bundle(
      type: fhir.BundleType.batchResponse, entry: resultEntries);
  FhirantLogging()
      .logInfo('Batch completed with ${resultEntries.length} entries');
  return Response.ok(resultBundle.toJsonString(),
      headers: {'Content-Type': 'application/json'});
}

/// Build a map of urn:uuid → ResourceType/id for all POST entries.
/// Pre-assigns IDs for resources that don't have them.
Map<String, String> _buildUrnUuidMap(List<fhir.BundleEntry> entries) {
  final map = <String, String>{};

  for (final entry in entries) {
    final fullUrl = entry.fullUrl?.toString() ?? '';
    if (!fullUrl.startsWith('urn:uuid:')) continue;
    if (entry.request?.method != fhir.HTTPVerb.pOST) continue;
    if (entry.resource == null) continue;

    final resource = entry.resource!;
    final resourceType = resource.resourceTypeString;
    final id = resource.id?.toString() ?? '';

    if (id.isNotEmpty) {
      map[fullUrl] = '$resourceType/$id';
    }
    // If no ID, it will be assigned by newIdIfNoId() during save;
    // we can't predict it here, so we skip pre-mapping.
    // The resource will get an ID during processing and the map
    // will be updated after the POST succeeds.
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

Future<_BundleOperation> _processBundleEntry(
  fhir.BundleEntry entry,
  FhirAntDb dbInterface,
  String baseUrl,
  int entryIndex,
  Map<String, String> urnMap,
) async {
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

  final urlParts = url.split('/').where((p) => p.isNotEmpty).toList();
  if (urlParts.isEmpty) {
    throw FormatException('Bundle entry $entryIndex: Invalid URL format');
  }

  final resourceType = urlParts[0];
  final resourceId = urlParts.length > 1 ? urlParts[1] : null;
  final resourceTypeEnum = fhir.R4ResourceType.fromString(resourceType);
  if (resourceTypeEnum == null) {
    throw FormatException(
        'Bundle entry $entryIndex: Invalid resource type: $resourceType');
  }

  fhir.Resource? resultResource;
  fhir.Resource? previousResource;
  fhir.Resource? createdResource;
  fhir.Resource? deletedResource;
  String status;
  String? location;

  switch (method) {
    case fhir.HTTPVerb.gET:
      if (resourceId == null) {
        throw FormatException(
            'Bundle entry $entryIndex: GET requires resource ID');
      }
      resultResource =
          await dbInterface.getResource(resourceTypeEnum, resourceId);
      if (resultResource == null) {
        throw FormatException(
            'Bundle entry $entryIndex: Resource not found');
      }
      status = '200';
      break;

    case fhir.HTTPVerb.pOST:
      if (entry.resource == null) {
        throw FormatException(
            'Bundle entry $entryIndex: POST requires resource');
      }
      if (entry.resource!.resourceTypeString != resourceType) {
        throw FormatException(
            'Bundle entry $entryIndex: Resource type mismatch');
      }

      // Conditional create: ifNoneExist
      final ifNoneExist = req.ifNoneExist?.valueString;
      if (ifNoneExist != null && ifNoneExist.isNotEmpty) {
        final searchParams = Uri.splitQueryString(ifNoneExist);
        final searchMap = <String, List<String>>{};
        for (final e in searchParams.entries) {
          searchMap[e.key] = [e.value];
        }
        final existing = await dbInterface.search(
          resourceType: resourceTypeEnum,
          searchParameters: searchMap,
        );
        if (existing.length == 1) {
          // Return existing resource
          resultResource = existing.first;
          status = '200';
          break;
        } else if (existing.length > 1) {
          throw FormatException(
              'Bundle entry $entryIndex: ifNoneExist matched multiple resources');
        }
        // 0 matches → proceed with create
      }

      // Resolve urn:uuid references in the resource
      var resourceJson = entry.resource!.toJson();
      if (urnMap.isNotEmpty) {
        resourceJson = _resolveUrnReferences(resourceJson, urnMap);
      }
      final resourceToSave = fhir.Resource.fromJson(resourceJson);

      final success = await dbInterface.saveResource(resourceToSave);
      if (!success) {
        throw FormatException(
            'Bundle entry $entryIndex: Failed to create resource');
      }

      // Re-fetch to get server-assigned meta
      final savedId = resourceToSave.id?.toString() ?? '';
      final saved =
          await dbInterface.getResource(resourceTypeEnum, savedId);
      resultResource = saved ?? resourceToSave;
      createdResource = resultResource;
      status = '201';
      location = '$baseUrl/$resourceType/${resultResource.id}';

      // Update urn map for subsequent entries
      final fullUrl = entry.fullUrl?.toString() ?? '';
      if (fullUrl.startsWith('urn:uuid:') &&
          !urnMap.containsKey(fullUrl)) {
        urnMap[fullUrl] =
            '$resourceType/${resultResource.id}';
      }
      break;

    case fhir.HTTPVerb.pUT:
      if (resourceId == null) {
        throw FormatException(
            'Bundle entry $entryIndex: PUT requires resource ID');
      }
      if (entry.resource == null) {
        throw FormatException(
            'Bundle entry $entryIndex: PUT requires resource');
      }
      if (entry.resource!.resourceTypeString != resourceType) {
        throw FormatException(
            'Bundle entry $entryIndex: Resource type mismatch');
      }
      final resourceIdFromBody = entry.resource!.id?.toString() ?? '';
      if (resourceIdFromBody != resourceId) {
        throw FormatException(
            'Bundle entry $entryIndex: Resource ID mismatch');
      }

      // Conditional update: ifMatch
      final ifMatch = req.ifMatch?.valueString;
      if (ifMatch != null && ifMatch.isNotEmpty) {
        final existingResource =
            await dbInterface.getResource(resourceTypeEnum, resourceId);
        if (existingResource != null) {
          final currentEtag = FhirHttpHeaders.etag(existingResource);
          if (currentEtag != ifMatch) {
            throw FormatException(
                'Bundle entry $entryIndex: ETag mismatch (ifMatch)');
          }
          previousResource = existingResource;
        }
      } else {
        // Capture previous version for rollback
        previousResource =
            await dbInterface.getResource(resourceTypeEnum, resourceId);
      }

      // Resolve urn:uuid references in the resource
      var putJson = entry.resource!.toJson();
      if (urnMap.isNotEmpty) {
        putJson = _resolveUrnReferences(putJson, urnMap);
      }
      final putResource = fhir.Resource.fromJson(putJson);

      final putSuccess = await dbInterface.saveResource(putResource);
      if (!putSuccess) {
        throw FormatException(
            'Bundle entry $entryIndex: Failed to update resource');
      }

      // Re-fetch to get server-assigned meta
      final updated =
          await dbInterface.getResource(resourceTypeEnum, resourceId);
      resultResource = updated ?? putResource;
      status = '200';
      break;

    case fhir.HTTPVerb.pATCH:
      if (resourceId == null) {
        throw FormatException(
            'Bundle entry $entryIndex: PATCH requires resource ID');
      }
      if (entry.resource == null) {
        throw FormatException(
            'Bundle entry $entryIndex: PATCH requires patch document');
      }

      final currentResource =
          await dbInterface.getResource(resourceTypeEnum, resourceId);
      if (currentResource == null) {
        throw FormatException(
            'Bundle entry $entryIndex: Resource not found for PATCH');
      }
      previousResource = currentResource;

      // Parse patch document from the entry resource
      List<dynamic> patchOperations;
      final patchResource = entry.resource!;
      if (patchResource.resourceTypeString == 'Binary') {
        // Binary: base64-decode the data field to get JSON Patch array
        final patchJson = patchResource.toJson();
        final data = patchJson['data'] as String?;
        if (data == null) {
          throw FormatException(
              'Bundle entry $entryIndex: Binary patch missing data field');
        }
        final decoded = utf8.decode(base64Decode(data));
        patchOperations = jsonDecode(decoded) as List<dynamic>;
      } else if (patchResource.resourceTypeString == 'Parameters') {
        patchOperations =
            convertFhirPatchToJsonPatch(patchResource.toJson());
      } else {
        throw FormatException(
            'Bundle entry $entryIndex: PATCH document must be Binary or Parameters');
      }

      final patchedJson =
          applyJsonPatch(currentResource.toJson(), patchOperations);
      final patchedResource = fhir.Resource.fromJson(patchedJson);

      // Validate type and ID unchanged
      if (patchedResource.resourceTypeString != resourceType) {
        throw FormatException(
            'Bundle entry $entryIndex: PATCH cannot change resource type');
      }
      final patchedId = patchedResource.id?.toString() ?? '';
      if (patchedId != resourceId) {
        throw FormatException(
            'Bundle entry $entryIndex: PATCH cannot change resource ID');
      }

      final patchSuccess = await dbInterface.saveResource(patchedResource);
      if (!patchSuccess) {
        throw FormatException(
            'Bundle entry $entryIndex: Failed to save patched resource');
      }

      final patchSaved =
          await dbInterface.getResource(resourceTypeEnum, resourceId);
      resultResource = patchSaved ?? patchedResource;
      status = '200';
      break;

    case fhir.HTTPVerb.dELETE:
      if (resourceId == null) {
        throw FormatException(
            'Bundle entry $entryIndex: DELETE requires resource ID');
      }

      final existingResource =
          await dbInterface.getResource(resourceTypeEnum, resourceId);
      if (existingResource == null) {
        throw FormatException(
            'Bundle entry $entryIndex: Resource not found for DELETE');
      }
      deletedResource = existingResource;

      final deleteSuccess =
          await dbInterface.deleteResource(resourceTypeEnum, resourceId);
      if (!deleteSuccess) {
        throw FormatException(
            'Bundle entry $entryIndex: Failed to delete resource');
      }

      resultResource = null;
      status = '204';
      break;

    default:
      throw FormatException(
          'Bundle entry $entryIndex: Unsupported HTTP method: $method');
  }

  // Build response with etag/lastModified for mutating operations
  fhir.FhirString? etag;
  fhir.FhirInstant? lastModified;
  if (resultResource != null &&
      method != fhir.HTTPVerb.gET) {
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
        ? fhir.FhirUri(
            '$baseUrl/$resourceType/${resultResource.id}')
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
  );
}

Future<void> _rollbackOperation(
    _BundleOperation operation, FhirAntDb dbInterface) async {
  switch (operation.method) {
    case fhir.HTTPVerb.pOST:
      // Delete the created resource
      if (operation.createdResource != null && operation.resourceId != null) {
        await dbInterface.deleteResource(
            operation.resourceType, operation.resourceId!);
        FhirantLogging().logInfo(
            'Rolled back POST: deleted ${operation.resourceType}/${operation.resourceId}');
      }
      break;
    case fhir.HTTPVerb.pUT:
    case fhir.HTTPVerb.pATCH:
      if (operation.previousResource != null) {
        // Restore previous version
        await dbInterface.saveResource(operation.previousResource!);
        FhirantLogging().logInfo(
            'Rolled back ${operation.method}: restored ${operation.resourceType}/${operation.resourceId}');
      } else if (operation.resourceId != null) {
        // No previous version means it was a create-via-PUT; delete it
        await dbInterface.deleteResource(
            operation.resourceType, operation.resourceId!);
        FhirantLogging().logInfo(
            'Rolled back create-via-PUT: deleted ${operation.resourceType}/${operation.resourceId}');
      }
      break;
    case fhir.HTTPVerb.dELETE:
      // Re-save the deleted resource
      if (operation.deletedResource != null) {
        await dbInterface.saveResource(operation.deletedResource!);
        FhirantLogging().logInfo(
            'Rolled back DELETE: re-saved ${operation.resourceType}/${operation.resourceId}');
      }
      break;
    default:
      // GET — nothing to rollback
      break;
  }
}

class _BundleOperation {
  final fhir.HTTPVerb method;
  final fhir.R4ResourceType resourceType;
  final String? resourceId;
  final fhir.BundleEntry resultEntry;
  final fhir.Resource? previousResource;
  final fhir.Resource? createdResource;
  final fhir.Resource? deletedResource;

  _BundleOperation({
    required this.method,
    required this.resourceType,
    required this.resourceId,
    required this.resultEntry,
    this.previousResource,
    this.createdResource,
    this.deletedResource,
  });
}

Response _errorResponse(String message, String details,
    {int statusCode = 500}) {
  final operationOutcome = fhir.OperationOutcome(issue: [
    fhir.OperationOutcomeIssue(
      severity: fhir.IssueSeverity.error,
      code: fhir.IssueType.exception,
      diagnostics: '$message: $details'.toFhirString,
    ),
  ]);
  FhirantLogging().logWarning('Error Response: $message - $details');
  return Response(statusCode,
      body: operationOutcome.toJsonString(),
      headers: {'Content-Type': 'application/json'});
}

Response _validationErrorResponse(String message) {
  final operationOutcome = fhir.OperationOutcome(issue: [
    fhir.OperationOutcomeIssue(
      severity: fhir.IssueSeverity.error,
      code: fhir.IssueType.processing,
      diagnostics: message.toFhirString,
    ),
  ]);
  FhirantLogging().logWarning('Validation Error: $message');
  return Response(400,
      body: operationOutcome.toJsonString(),
      headers: {'Content-Type': 'application/json'});
}
