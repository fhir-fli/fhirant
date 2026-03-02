import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/compartment_definitions.dart';
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

/// Checks if a resource is in the patient compartment for the given patient.
Future<bool> isInPatientCompartment(
  String resourceType,
  String resourceId,
  String patientId,
  FhirAntDb dbInterface,
) async {
  // Patient accessing their own record
  if (resourceType == 'Patient' && resourceId == patientId) return true;

  final compartmentDef = CompartmentDefinitions.getDefinition('Patient');
  if (compartmentDef == null || !compartmentDef.containsKey(resourceType)) {
    return false;
  }

  final paths = compartmentDef[resourceType]!;
  if (paths.isEmpty) return resourceId == patientId;

  final compartmentIds = await dbInterface.getCompartmentResourceIds(
    compartmentType: 'Patient',
    compartmentId: patientId,
    compartmentDefinition: {resourceType: paths},
  );

  return (compartmentIds[resourceType] ?? {}).contains(resourceId);
}

/// Returns a 403 response for patient scope violations.
Response patientScopeForbiddenResponse(
    String resourceType, String id, String patientId) {
  return Response(
    403,
    body: jsonEncode({
      'resourceType': 'OperationOutcome',
      'issue': [
        {
          'severity': 'error',
          'code': 'forbidden',
          'diagnostics':
              '$resourceType/$id is not in the patient compartment '
              'for Patient/$patientId',
        }
      ]
    }),
    headers: {'Content-Type': 'application/json'},
  );
}

/// Checks if a new resource (being created) would be in the patient compartment.
/// For POST (create), we check references within the resource JSON.
Future<bool> isNewResourceInPatientCompartment(
  String resourceType,
  Map<String, dynamic> resourceJson,
  String patientId,
) async {
  // Patient creating their own Patient resource
  if (resourceType == 'Patient') {
    final resourceId = resourceJson['id'] as String?;
    return resourceId == null || resourceId == patientId;
  }

  final compartmentDef = CompartmentDefinitions.getDefinition('Patient');
  if (compartmentDef == null || !compartmentDef.containsKey(resourceType)) {
    return false;
  }

  final paths = compartmentDef[resourceType]!;
  if (paths.isEmpty) return false; // Can't create focal resources in compartment

  // Check if any compartment path references the patient
  final patientRef = 'Patient/$patientId';
  for (final path in paths) {
    final value = _getNestedValue(resourceJson, path);
    if (value == null) continue;

    if (value is Map) {
      if (value['reference'] == patientRef) return true;
    } else if (value is List) {
      for (final item in value) {
        if (item is Map && item['reference'] == patientRef) return true;
      }
    }
  }

  return false;
}

dynamic _getNestedValue(Map<String, dynamic> json, String path) {
  final parts = path.split('.');
  dynamic current = json;

  for (final part in parts) {
    if (current is Map<String, dynamic>) {
      current = current[part];
      if (current == null) return null;
    } else if (current is List) {
      // Check first item in list
      if (current.isNotEmpty && current[0] is Map<String, dynamic>) {
        current = (current[0] as Map<String, dynamic>)[part];
      } else {
        return null;
      }
    } else {
      return null;
    }
  }
  return current;
}
