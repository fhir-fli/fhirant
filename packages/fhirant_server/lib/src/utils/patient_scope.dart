import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/smart_scopes.dart';
import 'package:shelf/shelf.dart';

/// Extracts the patient ID from the request context when the user has
/// patient-only scopes. Returns null if no patient restriction applies.
String? extractPatientContext(Request request) {
  final authUser = request.context['auth_user'] as Map<String, dynamic>?;
  if (authUser == null) return null;

  final scopes = authUser['scopes'] as List<String>?;
  if (scopes == null) return null;

  // Only enforce patient filtering if scopes are patient-only context
  if (!SmartScopeEnforcer.isPatientOnlyContext(scopes)) return null;

  return authUser['patientId'] as String?;
}

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

  final count = await dbInterface.searchCount(
    resourceType: type,
    searchParameters: {
      '_id': [resourceId],
    },
    compartment: patientCompartment(patientId),
  );
  return count > 0;
}

/// Returns a 403 response for patient scope violations.
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
) async {
  final resourceType = resource.resourceTypeString;
  // A patient creating their own Patient resource.
  if (resourceType == 'Patient') {
    final resourceId = resource.id?.valueString;
    return resourceId == null || resourceId == patientId;
  }

  final params = compartmentDefinitions['Patient']?[resourceType];
  if (params == null) return false;

  // The extractor reads meta.lastUpdated; a new resource may have no meta
  // yet, so it is versioned the way the save will version it.
  final indexed = updateSearchParameters(
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
