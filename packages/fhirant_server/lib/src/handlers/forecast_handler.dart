import 'dart:convert';

import 'package:cicada/cicada.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/utils/operation_outcomes.dart';
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
      return outcome(400, fhir.IssueType.invalid, 'Request body is required');
    }

    Map<String, dynamic> bodyJson;
    try {
      bodyJson = jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      return outcome(
        400,
        fhir.IssueType.invalid,
        'Invalid JSON in request body',
      );
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

      // ImmDSForecastOperation 1.0.0 (package hl7.fhir.us.immds 1.0.0, read
      // 2026-10-18): input `patient`, 1..1, a Patient. Without one the engine
      // threw and this answered 500 (REVIEW-2026-10-17 finding 15).
      if (!_hasPatientResource(bodyJson)) {
        return outcome(
          400,
          fhir.IssueType.required_,
          'The patient parameter (a Patient resource, or patientId naming '
          'a stored one) is required',
        );
      }

      final refusal = _unforecastable(bodyJson);
      if (refusal != null) return refusal;

      // The client's resources are read here, outside the catch-all below,
      // so one the model cannot read is the client's 400 and not the
      // server's 500 (R4B http.html 3.1.0.4.2, "400 Bad Request - resource
      // could not be parsed"; REVIEW-2026-10-17, phone run).
      final fhir.Parameters parsed;
      try {
        parsed = fhir.Parameters.fromJson(bodyJson);
      } catch (e) {
        return validationOutcome('Invalid Parameters: $e');
      }

      final result = forecastFromParameters(parsed, mode: mode);

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

      final refusal = _unforecastable(parameters);
      if (refusal != null) return refusal;

      final result = forecastFromMap(parameters, mode: mode);

      FhirantLogging().logInfo(
        '\$immds-forecast ($modeName) completed successfully',
      );

      return Response.ok(
        jsonEncode(result.toJson()),
        headers: {'Content-Type': 'application/fhir+json'},
      );
    }

    return outcome(
      400,
      fhir.IssueType.invalid,
      'Expected a Parameters resource or JSON with patientId',
    );
  } on PatientNotFound catch (e) {
    // A patient the request names and the store does not hold is a 404, not
    // a 500 (REVIEW-2026-09-08 row 32).
    return outcome(404, fhir.IssueType.notFound, 'Patient/${e.id} not found');
  } catch (e, stackTrace) {
    FhirantLogging().logError('Immunization forecast failed', e, stackTrace);
    return outcome(
      500,
      fhir.IssueType.exception,
      'Immunization forecast error',
    );
  }
}

/// The Patient a forecast request named is not in the store.
class PatientNotFound implements Exception {
  /// Creates the exception for [id].
  const PatientNotFound(this.id);

  /// The logical id that was not found.
  final String id;
}

/// A 422 when the request holds what the engine cannot evaluate, else null.
///
/// - A Patient with no birthDate. CDSi Logic Specification v4.6 gives Date
///   of Birth no assumed value (Tables 5-2, 6-14, 7-2: "Assumed Value if
///   Empty" "-") and computes every age date from it (Table 3-6,
///   CALCDTAGE-1..5). The engine used to assume 1900-01-01 and answer a full
///   forecast (REVIEW-2026-10-17 finding 7).
/// - A dose with no occurrenceDateTime. R4B Immunization.occurrence[x] may
///   be a string; CDSi gives Date Administered no assumed value (Tables 3-4,
///   6-2), and the engine used to date such a dose 2999-01-01.
/// - A dose with no id. R4B ImmunizationEvaluation.immunizationEvent is 1..1
///   (profiles-resources.json, read 2026-10-18) and the engine names the
///   dose by id; it stopped on a null check and this answered 500
///   (REVIEW-2026-10-17, phone run).
Response? _unforecastable(Map<String, dynamic> params) {
  Response refuse(String message) =>
      outcome(422, fhir.IssueType.businessRule, message);
  for (final p in (params['parameter'] as List<dynamic>?) ?? const []) {
    if (p is! Map<String, dynamic>) continue;
    final resource = p['resource'];
    if (resource is! Map<String, dynamic>) continue;
    switch (resource['resourceType']) {
      case 'Patient':
        final birthDate = resource['birthDate'];
        if (birthDate is! String || birthDate.isEmpty) {
          return refuse(
            'The Patient has no birthDate; an immunization forecast is '
            'computed from the date of birth (CDSi assumes none)',
          );
        }
      case 'Immunization':
        final id = resource['id'];
        if (id is! String || id.isEmpty) {
          return refuse(
            'An Immunization has no id; each evaluation names the dose it '
            'evaluates (ImmunizationEvaluation.immunizationEvent 1..1)',
          );
        }
        final occurrence = resource['occurrenceDateTime'];
        if (occurrence is! String || occurrence.isEmpty) {
          return refuse(
            'Immunization/$id has no occurrenceDateTime; a dose is evaluated '
            'from its date administered (CDSi assumes none)',
          );
        }
    }
  }
  return null;
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
    throw PatientNotFound(id);
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
///
/// A read that throws is thrown on, and the request answers 500. It used to
/// be caught and answered as an empty list (REVIEW-2026-09-17 F1): a failed
/// Immunization read became "no doses given" and every dose was forecast as
/// due, a failed Condition or AllergyIntolerance read dropped the
/// contraindications, and the 200 said nothing of either.
Future<List<fhir.Resource>> _searchForPatient(
  fhir.R4ResourceType type,
  String patientId,
  FhirAntDb dbInterface,
) =>
    dbInterface.search(
      resourceType: type,
      searchParameters: {
        'patient': ['Patient/$patientId'],
      },
    );
