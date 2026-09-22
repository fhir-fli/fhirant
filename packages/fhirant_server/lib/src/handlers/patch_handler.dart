import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/auth/request_authorization.dart';
import 'package:fhirant_server/src/services/subscription_service.dart';
import 'package:fhirant_server/src/utils/http_headers.dart';
import 'package:fhirant_server/src/utils/json_patch.dart';
import 'package:fhirant_server/src/utils/operation_outcomes.dart';
import 'package:fhirant_server/src/utils/patient_scope.dart';
import 'package:fhirant_server/src/utils/stored_resource.dart';
import 'package:shelf/shelf.dart';

/// Handler for PATCH operation: PATCH /{resourceType}/{id}
/// Supports JSON Patch (RFC 6902)
Future<Response> patchResourceHandler(
  Request request,
  String resourceType,
  String id,
  FhirAntDb dbInterface, {
  SubscriptionService? subscriptions,
}) async {
  // Every write goes through the Subscription service, as PUT and POST do:
  // a Subscription's status is the server's to set, and a change notifies
  // its subscribers. PATCH took no service, so a client could PATCH a
  // Subscription the server had set `error` back to `active`, and a PATCH
  // of any resource notified nobody (REVIEW-2026-09-17 A7).
  final subs = subscriptions ?? SubscriptionService(dbInterface);
  try {
    FhirantLogging().logInfo(
      'Patching resource: $resourceType/{id}',
    );

    final lookup = await lookupStored(
      request,
      dbInterface,
      resourceType,
      id,
      permission: 'u',
    );
    if (lookup is! StoredFound) return lookupRefusal(lookup);
    final currentResource = lookup.resource;
    // Re-read below for the patched body's own compartment check.
    final patchPatientId = patientContextFor(request, resourceType, 'u');

    // Read and parse the patch document
    final body = await request.readAsString();
    List<dynamic> patchOperations;
    try {
      final patchDoc = jsonDecode(body) as dynamic;
      if (patchDoc is List) {
        patchOperations = patchDoc;
      } else if (patchDoc is Map && patchDoc['resourceType'] == 'Parameters') {
        // FHIRPath Patch (a Parameters body) is not implemented. It used to
        // be converted by dropping the type prefix and turning dots into
        // slashes, which handles no `where()` and no index, so most patches
        // applied to the wrong element or failed obscurely
        // (REVIEW-2026-09-06 finding 23). The CapabilityStatement advertises
        // JSON Patch only; a Parameters body is refused as a media type
        // this server does not support.
        return _fhirPatchNotSupported();
      } else {
        return validationOutcome(
          'Invalid patch format. Expected JSON Patch array or FHIR '
          'Parameters resource.',
        );
      }
    } catch (e) {
      FhirantLogging().logError('Error parsing patch document: $e');
      return validationOutcome('Invalid JSON in patch document: $e');
    }

    // Convert resource to JSON for patching
    final resourceJson = currentResource.toJson();

    // Apply patch operations
    try {
      final patchedJson = applyJsonPatch(resourceJson, patchOperations);

      // Convert back to resource
      final patchedResource = fhir.Resource.fromJson(patchedJson);

      // Validate resource type and ID haven't changed
      if (patchedResource.resourceTypeString != resourceType) {
        return validationOutcome(
          'Patch operation cannot change resource type',
        );
      }

      final resourceId = patchedResource.id?.toString() ?? '';
      if (resourceId != id) {
        return validationOutcome(
          'Patch operation cannot change resource ID',
        );
      }

      final storeRefused = storeRefusal(Principal.of(request), patchedResource);
      if (storeRefused != null) return storeRefused;

      // The patched resource must still be in the compartment, as a PUT's
      // body must (REVIEW-2026-09-08 row 11).
      if (patchPatientId != null &&
          !await isNewResourceInPatientCompartment(
            patchedResource,
            patchPatientId,
          )) {
        return patientScopeForbiddenResponse(resourceType, id, patchPatientId);
      }

      // Save the patched resource (creates new version automatically). The
      // If-Match version is checked inside the store's write, the same
      // compare-and-swap as PUT: http.html §3.1.0.13 (read 2026-09-08),
      // "servers SHALL support conditional PATCH, which works exactly the
      // same as specified for update in Concurrency Management". PATCH used
      // to ignore the header (REVIEW-2026-09-08 row 22).
      final toSave = patchedResource is fhir.Subscription
          ? await subs.activate(patchedResource)
          : patchedResource;
      final fhir.Resource savedResource;
      try {
        savedResource = await dbInterface.saveResource(
          toSave,
          ifMatchVersion:
              FhirHttpHeaders.parseETag(request.headers['if-match']),
        );
      } on InvalidSearchParameter catch (e) {
        return invalidSearchParameter(e);
      } on VersionConflict {
        return Response(
          412,
          body: fhir.OperationOutcome(
            issue: [
              fhir.OperationOutcomeIssue(
                severity: fhir.IssueSeverity.error,
                code: fhir.IssueType.conflict,
                diagnostics: 'Version mismatch (If-Match precondition failed)'
                    .toFhirString,
              ),
            ],
          ).toJsonString(),
          headers: {'Content-Type': 'application/fhir+json'},
        );
      } catch (e, stackTrace) {
        // The store failed, not the patch: the server's 500. Inside the
        // enclosing catch this was answered as the client's 400
        // (REVIEW-2026-09-17 ST7).
        FhirantLogging().logError(
          'Failed to save patched resource: $resourceType/{id}',
          e,
          stackTrace,
        );
        return exceptionOutcome(
          'Failed to save patched resource',
          'Internal error',
        );
      }
      await subs.onResourceChanged(savedResource);

      final responseResource = savedResource;

      FhirantLogging().logInfo(
        'Successfully patched resource: $resourceType/{id}',
      );

      final preference = FhirHttpHeaders.parsePreferReturn(request.headers);
      return FhirHttpHeaders.preferredResponse(
        statusCode: 200,
        resource: responseResource,
        headers: FhirHttpHeaders.resourceHeaders(responseResource),
        preference: preference,
      );
    } catch (e, stackTrace) {
      FhirantLogging().logError(
        'Error applying patch to resource: $resourceType/{id}',
        e,
        stackTrace,
      );
      return exceptionOutcome(
        'Failed to apply patch',
        e.toString(),
        statusCode: 400,
      );
    }
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error processing PATCH request for: $resourceType/{id}',
      e,
      stackTrace,
    );
    return exceptionOutcome(
      'Error processing PATCH request',
      'Internal error',
    );
  }
}

/// 415 for a FHIRPath Patch body: the CapabilityStatement's patchFormat is
/// `application/json-patch+json` only.
Response _fhirPatchNotSupported() => Response(
      415,
      body: fhir.OperationOutcome(
        issue: [
          fhir.OperationOutcomeIssue(
            severity: fhir.IssueSeverity.error,
            code: fhir.IssueType.notSupported,
            diagnostics: 'FHIRPath Patch (a Parameters body) is not '
                    'supported; send a JSON Patch document '
                    '(application/json-patch+json).'
                .toFhirString,
          ),
        ],
      ).toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
