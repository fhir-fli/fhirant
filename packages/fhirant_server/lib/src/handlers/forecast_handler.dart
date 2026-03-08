import 'dart:convert';

import 'package:cicada/cicada.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:shelf/shelf.dart';

/// Immunization forecast handler — CDC CDSi logic.
///
/// Route: `POST /$immds-forecast`
///
/// Accepts a FHIR Parameters resource containing Patient, Immunization,
/// Condition, and AllergyIntolerance resources. Returns a Parameters resource
/// with ImmunizationEvaluation and ImmunizationRecommendation results.
///
/// Alternatively, pass `patientId` to auto-load from the database.
Future<Response> immdsForecastHandler(
  Request request,
  FhirAntDb dbInterface,
) async {
  return _handleForecast(request, dbInterface, ForecastMode.cdc);
}

/// Immunization forecast handler — WHO EPI logic.
///
/// Route: `POST /$immds-forecast-who`
Future<Response> immdsForecastWhoHandler(
  Request request,
  FhirAntDb dbInterface,
) async {
  return _handleForecast(request, dbInterface, ForecastMode.who);
}

Future<Response> _handleForecast(
  Request request,
  FhirAntDb dbInterface,
  ForecastMode mode,
) async {
  try {
    final modeName = mode == ForecastMode.cdc ? 'CDC' : 'WHO';
    FhirantLogging().logInfo('Received \$immds-forecast request ($modeName)');

    final body = await request.readAsString();
    if (body.isEmpty) {
      return _errorResponse(400, 'invalid', 'Request body is required');
    }

    Map<String, dynamic> bodyJson;
    try {
      bodyJson = jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      return _errorResponse(400, 'invalid', 'Invalid JSON in request body');
    }

    // If the body is already a Parameters resource, use it directly
    if (bodyJson['resourceType'] == 'Parameters') {
      // Check if they passed a patientId param instead of a Patient resource
      final patientIdParam = _extractPatientId(bodyJson);
      if (patientIdParam != null && !_hasPatientResource(bodyJson)) {
        bodyJson = await _buildParametersFromDb(
          patientIdParam,
          bodyJson,
          dbInterface,
        );
      }

      final result = forecastFromMap(bodyJson, mode: mode);

      FhirantLogging().logInfo(
        '\$immds-forecast ($modeName) completed successfully',
      );

      return Response.ok(
        jsonEncode(result.toJson()),
        headers: {'Content-Type': 'application/fhir+json'},
      );
    }

    // Plain JSON with patientId — build Parameters from DB
    final patientId = bodyJson['patientId'] as String?;
    if (patientId != null) {
      final parameters = await _buildParametersFromDb(
        patientId,
        null,
        dbInterface,
      );
      final assessmentDate = bodyJson['assessmentDate'] as String?;
      if (assessmentDate != null) {
        (parameters['parameter'] as List).insert(0, {
          'name': 'assessmentDate',
          'valueDate': assessmentDate,
        });
      }

      final result = forecastFromMap(parameters, mode: mode);

      FhirantLogging().logInfo(
        '\$immds-forecast ($modeName) completed successfully',
      );

      return Response.ok(
        jsonEncode(result.toJson()),
        headers: {'Content-Type': 'application/fhir+json'},
      );
    }

    return _errorResponse(
      400,
      'invalid',
      'Expected a Parameters resource or JSON with patientId',
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('Immunization forecast failed', e, stackTrace);
    return _errorResponse(
      500,
      'exception',
      'Immunization forecast error: ${e.toString()}',
    );
  }
}

/// Check if the Parameters resource already contains a Patient resource.
bool _hasPatientResource(Map<String, dynamic> params) {
  final paramList = params['parameter'] as List<dynamic>? ?? [];
  return paramList.any((p) {
    if (p is! Map<String, dynamic>) return false;
    final resource = p['resource'] as Map<String, dynamic>?;
    return resource?['resourceType'] == 'Patient';
  });
}

/// Extract a patientId string from a Parameters resource (if present).
String? _extractPatientId(Map<String, dynamic> params) {
  final paramList = params['parameter'] as List<dynamic>? ?? [];
  for (final p in paramList) {
    if (p is! Map<String, dynamic>) continue;
    if (p['name'] == 'patientId') {
      return p['valueString'] as String?;
    }
  }
  return null;
}

/// Build a Cicada-compatible Parameters resource by loading Patient,
/// Immunizations, Conditions, and AllergyIntolerances from the database.
Future<Map<String, dynamic>> _buildParametersFromDb(
  String patientId,
  Map<String, dynamic>? existingParams,
  FhirAntDb dbInterface,
) async {
  // Strip "Patient/" prefix if present
  final id =
      patientId.startsWith('Patient/') ? patientId.substring(8) : patientId;

  final patient = await dbInterface.getResource(
    fhir.R4ResourceType.Patient,
    id,
  );
  if (patient == null) {
    throw Exception('Patient not found: $id');
  }

  final parameters = <Map<String, dynamic>>[];

  // Preserve existing params (except patientId which we're resolving)
  if (existingParams != null) {
    final existing = existingParams['parameter'] as List<dynamic>? ?? [];
    for (final p in existing) {
      if (p is Map<String, dynamic> && p['name'] != 'patientId') {
        parameters.add(p);
      }
    }
  }

  // Add Patient resource
  parameters.add({
    'name': 'patient',
    'resource': patient.toJson(),
  });

  // Load Immunizations for this patient
  final immunizations = await _searchForPatient(
    fhir.R4ResourceType.Immunization,
    id,
    dbInterface,
  );
  for (final imm in immunizations) {
    parameters.add({
      'name': 'immunization',
      'resource': imm.toJson(),
    });
  }

  // Load Conditions
  final conditions = await _searchForPatient(
    fhir.R4ResourceType.Condition,
    id,
    dbInterface,
  );
  for (final cond in conditions) {
    parameters.add({
      'name': 'condition',
      'resource': cond.toJson(),
    });
  }

  // Load AllergyIntolerances
  final allergies = await _searchForPatient(
    fhir.R4ResourceType.AllergyIntolerance,
    id,
    dbInterface,
  );
  for (final allergy in allergies) {
    parameters.add({
      'name': 'allergyIntolerance',
      'resource': allergy.toJson(),
    });
  }

  return {
    'resourceType': 'Parameters',
    'parameter': parameters,
  };
}

/// Search for resources belonging to a specific patient.
Future<List<fhir.Resource>> _searchForPatient(
  fhir.R4ResourceType type,
  String patientId,
  FhirAntDb dbInterface,
) async {
  try {
    return await dbInterface.search(
      resourceType: type,
      searchParameters: {'patient': ['Patient/$patientId']},
    );
  } catch (_) {
    return [];
  }
}

Response _errorResponse(int status, String code, String diagnostics) {
  return Response(
    status,
    body: jsonEncode({
      'resourceType': 'OperationOutcome',
      'issue': [
        {
          'severity': 'error',
          'code': code,
          'diagnostics': diagnostics,
        }
      ],
    }),
    headers: {'Content-Type': 'application/fhir+json'},
  );
}
