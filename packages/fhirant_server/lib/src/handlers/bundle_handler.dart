import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
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
    FhirantLogging().logError('Error processing Bundle request', e, stackTrace);
    return _errorResponse('Failed to process Bundle', e.toString(), statusCode: 400);
  }
}

Future<Response> _processTransaction(
  fhir.Bundle bundle,
  FhirAntDb dbInterface,
  Request request,
) async {
  FhirantLogging().logInfo('Processing Transaction Bundle with ${bundle.entry!.length} entries');
  final baseUrl = '${request.requestedUri.scheme}://${request.requestedUri.host}:${request.requestedUri.port}';
  final resultEntries = <fhir.BundleEntry>[];
  final operations = <_BundleOperation>[];

  for (var i = 0; i < bundle.entry!.length; i++) {
    final entry = bundle.entry![i];
    if (entry.request == null) {
      return _validationErrorResponse('Bundle entry $i missing request');
    }

    try {
      final operation = await _processBundleEntry(entry, dbInterface, baseUrl, i);
      operations.add(operation);
      resultEntries.add(operation.resultEntry);
    } catch (e, stackTrace) {
      FhirantLogging().logError('Transaction failed at entry $i, rolling back', e, stackTrace);
      for (var j = operations.length - 1; j >= 0; j--) {
        try {
          await _rollbackOperation(operations[j], dbInterface);
        } catch (rollbackError) {
          FhirantLogging().logError('Error during rollback of operation $j', rollbackError);
        }
      }
      return _errorResponse('Transaction failed at entry $i', e.toString(), statusCode: 400);
    }
  }

  final resultBundle = fhir.Bundle(type: fhir.BundleType.transactionResponse, entry: resultEntries);
  FhirantLogging().logInfo('Transaction completed successfully with ${resultEntries.length} entries');
  return Response.ok(resultBundle.toJsonString(), headers: {'Content-Type': 'application/json'});
}

Future<Response> _processBatch(
  fhir.Bundle bundle,
  FhirAntDb dbInterface,
  Request request,
) async {
  FhirantLogging().logInfo('Processing Batch Bundle with ${bundle.entry!.length} entries');
  final baseUrl = '${request.requestedUri.scheme}://${request.requestedUri.host}:${request.requestedUri.port}';
  final resultEntries = <fhir.BundleEntry>[];

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
      final operation = await _processBundleEntry(entry, dbInterface, baseUrl, i);
      resultEntries.add(operation.resultEntry);
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

  final resultBundle = fhir.Bundle(type: fhir.BundleType.batchResponse, entry: resultEntries);
  FhirantLogging().logInfo('Batch completed with ${resultEntries.length} entries');
  return Response.ok(resultBundle.toJsonString(), headers: {'Content-Type': 'application/json'});
}

Future<_BundleOperation> _processBundleEntry(
  fhir.BundleEntry entry,
  FhirAntDb dbInterface,
  String baseUrl,
  int entryIndex,
) async {
  final req = entry.request!;
  final method = req.method;
  final url = req.url.toString();

  final urlParts = url.split('/').where((p) => p.isNotEmpty).toList();
  if (urlParts.isEmpty) throw FormatException('Bundle entry $entryIndex: Invalid URL format');

  final resourceType = urlParts[0];
  final resourceId = urlParts.length > 1 ? urlParts[1] : null;
  final resourceTypeEnum = fhir.R4ResourceType.fromString(resourceType);
  if (resourceTypeEnum == null) {
    throw FormatException('Bundle entry $entryIndex: Invalid resource type: $resourceType');
  }

  fhir.Resource? resultResource;
  String status;
  String? location;

  switch (method) {
    case fhir.HTTPVerb.gET:
      if (resourceId == null) throw FormatException('Bundle entry $entryIndex: GET requires resource ID');
      resultResource = await dbInterface.getResource(resourceTypeEnum, resourceId);
      if (resultResource == null) throw FormatException('Bundle entry $entryIndex: Resource not found');
      status = '200';
      break;

    case fhir.HTTPVerb.pOST:
      if (entry.resource == null) throw FormatException('Bundle entry $entryIndex: POST requires resource');
      if (entry.resource!.resourceTypeString != resourceType) {
        throw FormatException('Bundle entry $entryIndex: Resource type mismatch');
      }
      final success = await dbInterface.saveResource(entry.resource!);
      if (!success) throw FormatException('Bundle entry $entryIndex: Failed to create resource');
      resultResource = entry.resource;
      status = '201';
      location = '$baseUrl/$resourceType/${entry.resource!.id}';
      break;

    case fhir.HTTPVerb.pUT:
      if (resourceId == null) throw FormatException('Bundle entry $entryIndex: PUT requires resource ID');
      if (entry.resource == null) throw FormatException('Bundle entry $entryIndex: PUT requires resource');
      if (entry.resource!.resourceTypeString != resourceType) {
        throw FormatException('Bundle entry $entryIndex: Resource type mismatch');
      }
      final resourceIdFromBody = entry.resource!.id?.toString() ?? '';
      if (resourceIdFromBody != resourceId) {
        throw FormatException('Bundle entry $entryIndex: Resource ID mismatch');
      }
      final success = await dbInterface.saveResource(entry.resource!);
      if (!success) throw FormatException('Bundle entry $entryIndex: Failed to update resource');
      resultResource = entry.resource;
      status = '200';
      break;

    case fhir.HTTPVerb.pATCH:
      throw FormatException('Bundle entry $entryIndex: PATCH not yet supported in Bundles');

    case fhir.HTTPVerb.dELETE:
      throw FormatException('Bundle entry $entryIndex: DELETE not supported (data retention policy)');

    default:
      throw FormatException('Bundle entry $entryIndex: Unsupported HTTP method: $method');
  }

  final resultEntry = fhir.BundleEntry(
    response: fhir.BundleResponse(
      status: status.toFhirString,
      location: location != null ? fhir.FhirUri(location) : null,
    ),
    resource: resultResource,
    fullUrl: resultResource != null ? fhir.FhirUri('$baseUrl/$resourceType/${resultResource.id}') : null,
  );

  return _BundleOperation(
    method: method,
    resourceType: resourceTypeEnum,
    resourceId: resourceId,
    resultEntry: resultEntry,
  );
}

Future<void> _rollbackOperation(_BundleOperation operation, FhirAntDb dbInterface) async {
  if (operation.method == fhir.HTTPVerb.pOST) {
    FhirantLogging().logWarning(
      'Cannot fully rollback POST operation for ${operation.resourceType}/${operation.resourceId} '
      '(DELETE not supported for data retention)',
    );
  } else if (operation.method == fhir.HTTPVerb.pUT) {
    FhirantLogging().logInfo(
      'Rollback PUT operation for ${operation.resourceType}/${operation.resourceId} '
      '(previous version should be restored from history)',
    );
  }
}

class _BundleOperation {
  final fhir.HTTPVerb method;
  final fhir.R4ResourceType resourceType;
  final String? resourceId;
  final fhir.BundleEntry resultEntry;

  _BundleOperation({
    required this.method,
    required this.resourceType,
    required this.resourceId,
    required this.resultEntry,
  });
}

Response _errorResponse(String message, String details, {int statusCode = 500}) {
  final operationOutcome = fhir.OperationOutcome(issue: [
    fhir.OperationOutcomeIssue(
      severity: fhir.IssueSeverity.error,
      code: fhir.IssueType.exception,
      diagnostics: (message + ': ' + details).toFhirString,
    ),
  ]);
  FhirantLogging().logWarning('Error Response: \$message - \$details');
  return Response(statusCode, body: operationOutcome.toJsonString(), headers: {'Content-Type': 'application/json'});
}

Response _validationErrorResponse(String message) {
  final operationOutcome = fhir.OperationOutcome(issue: [
    fhir.OperationOutcomeIssue(
      severity: fhir.IssueSeverity.error,
      code: fhir.IssueType.processing,
    ),
  ]);
  FhirantLogging().logWarning('Validation Error: \$message');
  return Response(400, body: operationOutcome.toJsonString(), headers: {'Content-Type': 'application/json'});
}
