import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/auth/request_authorization.dart';
import 'package:fhirant_server/src/utils/operation_outcomes.dart';
import 'package:shelf/shelf.dart';

/// The Patient a request is confined to for [permission] on [resourceType],
/// or null when nothing confines it: [Principal.compartmentFor], read off
/// the request. The decision is per type and permission (REVIEW-2026-09-08
/// row 3); it used to be per token, lifted by any `user/` scope anywhere.
String? patientContextFor(
  Request request,
  String resourceType,
  String permission,
) =>
    Principal.of(request)?.compartmentFor(resourceType, permission)?.id;

/// The compartment a patient-scoped token confines a request to.
CompartmentScope patientCompartment(String patientId) =>
    CompartmentScope('Patient', patientId);

/// Whether the stored `[resourceType]/[resourceId]` is in [patientId]'s
/// compartment.
///
/// One scoped count on the store: `_id=[resourceId]` inside
/// `CompartmentScope('Patient', patientId)`, which the store answers from
/// the reference index through the parameters the published
/// CompartmentDefinition names for the type. A type the compartment does not
/// include counts 0. This used to fetch every id in the compartment for the
/// type and look the one id up in Dart.
Future<bool> isInPatientCompartment(
  String resourceType,
  String resourceId,
  String patientId,
  FhirAntDb dbInterface,
) async {
  // Patient accessing their own record
  if (resourceType == 'Patient' && resourceId == patientId) return true;

  final type = fhir.R4ResourceType.fromString(resourceType);
  if (type == null) return false;

  if (type == fhir.R4ResourceType.Binary) {
    final binary = await dbInterface.getResource(type, resourceId);
    return binary is fhir.Binary &&
        await _binaryInPatientCompartment(binary, patientId, dbInterface);
  }

  final count = await dbInterface.searchCount(
    resourceType: type,
    searchParameters: {
      '_id': [resourceId],
    },
    compartment: patientCompartment(patientId),
  );
  return count > 0;
}

/// The answer to a READ of a resource outside the caller's patient
/// compartment: the route's ordinary 404, byte for byte, so the caller
/// cannot tell what it may not see from what does not exist.
///
/// R4B security.html, "Access Denied Response Handling" (read 2026-09-19,
/// verbatim): "Return a 404 'Not Found' - This also protects from data
/// leakage as it is indistinguishable from a query against a resource that
/// doesn't exist." A patient token used to get 403 for another patient's
/// resource, 404 for an absent one and 410 for a deleted one
/// (REVIEW-2026-09-17 A13). Writes keep [patientScopeForbiddenResponse]:
/// a PUT, PATCH or DELETE of another patient's resource is a refusal of
/// the act, and answering "not found" to a PUT would mean create.
Response patientScopeNotFoundResponse(String resourceType, String id) =>
    notFoundOutcome('$resourceType/$id');

/// Returns a 403 response for a WRITE outside the patient compartment.
Response patientScopeForbiddenResponse(
  String resourceType,
  String id,
  String patientId,
) {
  return Response(
    403,
    body: jsonEncode({
      'resourceType': 'OperationOutcome',
      'issue': [
        {
          'severity': 'error',
          'code': 'forbidden',
          'diagnostics': '$resourceType/$id is not in the patient compartment '
              'for Patient/$patientId',
        }
      ],
    }),
    headers: {'Content-Type': 'application/json'},
  );
}

/// Whether a resource about to be created would be in [patientId]'s
/// compartment.
///
/// The resource is not stored yet, so the question is put to the same
/// extractor that will index it: its reference rows are computed, and it is
/// in the compartment when one of them is on a parameter the published
/// CompartmentDefinition names for its type and points at `Patient/[id]`.
/// This used to walk the JSON by hand along a hand-written path list, and
/// looked only at the FIRST element of any array on the way, so a resource
/// whose second performer was the patient was refused.
Future<bool> isNewResourceInPatientCompartment(
  fhir.Resource resource,
  String patientId,
  FhirAntDb dbInterface,
) async {
  final resourceType = resource.resourceTypeString;
  // A patient creating their own Patient resource.
  if (resourceType == 'Patient') {
    final resourceId = resource.id?.valueString;
    return resourceId == null || resourceId == patientId;
  }
  if (resource is fhir.Binary) {
    return _binaryInPatientCompartment(resource, patientId, dbInterface);
  }

  final params = compartmentDefinitions['Patient']?[resourceType];
  if (params == null) return false;

  // The extractor reads meta.lastUpdated; a new resource may have no meta
  // yet, so it is versioned the way the save will version it.
  final indexed = updateSearchParameters(
    r4Model.indexer,
    resource.meta?.lastUpdated == null
        ? resource.updateVersion(oldMeta: resource.meta)
        : resource,
  );
  for (final row in indexed.referenceParams) {
    if (!params.contains(row.searchName.value)) continue;
    if (row.referenceResourceType.value != 'Patient') continue;
    if (row.referenceIdPart.value == patientId) return true;
  }
  return false;
}

/// Whether [binary] is in [patientId]'s compartment, through its
/// securityContext.
///
/// Binary is in no Patient CompartmentDefinition. R4B binary.html (read
/// 2026-10-18, verbatim) gives securityContext the job instead: it
/// "identifies another resource that can be used as a proxy of the security
/// sensitivity to use when deciding and enforcing access control rules for
/// the Binary resource ... E.g. to identify that the binary resource relates
/// to a patient, and access should only be granted to applications that have
/// access to the patient", and tells the server "that the Binary resource
/// should be treated as if it was the other resource". So a Binary is in the
/// compartment when its securityContext is `Patient/[patientId]`, or a
/// resource in the compartment (a version suffix dropped). No context, a
/// context that is another Binary, or one that is not `[type]/[id]` here,
/// puts it in no compartment, as before. A patient-scoped token used to get
/// 404 on every Binary, its own patient's included (found 2026-10-18).
Future<bool> _binaryInPatientCompartment(
  fhir.Binary binary,
  String patientId,
  FhirAntDb dbInterface,
) async {
  final reference = binary.securityContext?.reference?.valueString;
  if (reference == null) return false;
  final parts = reference.split('/');
  if (parts.length != 2 && !(parts.length == 4 && parts[2] == '_history')) {
    return false;
  }
  final (type, id) = (parts[0], parts[1]);
  if (type == 'Binary') return false;
  return isInPatientCompartment(type, id, patientId, dbInterface);
}
