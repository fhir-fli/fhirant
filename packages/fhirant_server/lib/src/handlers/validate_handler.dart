import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhir_r4_validation/fhir_r4_validation.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/utils/db_resource_cache.dart';
import 'package:shelf/shelf.dart';

/// `$validate`, per `OperationDefinition/Resource-validate`.
///
/// The operation takes `resource`, `mode` and `profile`. Of those, `profile`
/// is the one with teeth:
///
/// > If this is nominated, then the resource is validated against this
/// > specific profile. If a profile is nominated, and the server cannot
/// > validate against the nominated profile, it SHALL return an error.
///
/// A nominated profile is therefore never ignored. Ignoring it would report a
/// base-type pass as though the profile had been checked, which is a wrong
/// answer to the question the client asked.
///
/// The request body may be the resource itself, or a `Parameters` carrying
/// `resource` and `profile`. `profile` may also arrive as a query parameter.
Future<Response> validateHandler(
  Request request,
  FhirAntDb? dbInterface, [
  String? resourceType,
]) async {
  try {
    FhirantLogging().logInfo('Received validation request');

    final body = await request.readAsString();
    if (body.isEmpty) {
      return _outcome(400, 'invalid', 'Request body is empty');
    }

    Map<String, dynamic> bodyJson;
    try {
      bodyJson = jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      return _outcome(400, 'invalid', 'Invalid JSON format: $e');
    }

    // A Parameters body carries the resource and the profile separately.
    var resourceJson = bodyJson;
    String? profile;
    if (bodyJson['resourceType'] == 'Parameters') {
      final parts = (bodyJson['parameter'] as List?) ?? const [];
      for (final part in parts.whereType<Map<String, dynamic>>()) {
        switch (part['name']) {
          case 'resource':
            final nested = part['resource'];
            if (nested is Map<String, dynamic>) {
              resourceJson = nested;
            }
          case 'profile':
            // `profile` is a canonical. Clients that send it as a uri or a
            // string are read too, rather than silently validating without
            // the profile they asked for.
            profile = (part['valueCanonical'] ??
                part['valueUri'] ??
                part['valueString']) as String?;
        }
      }
      if (identical(resourceJson, bodyJson)) {
        return _outcome(
          400,
          'invalid',
          'Parameters body carries no "resource" parameter',
        );
      }
    }

    profile ??= request.url.queryParameters['profile'];

    if (resourceType != null) {
      final bodyResourceType = resourceJson['resourceType'];
      if (bodyResourceType != resourceType) {
        return _outcome(
          400,
          'invalid',
          'Resource type in body ($bodyResourceType) does not match URL path '
              '($resourceType)',
        );
      }
    }

    fhir.StructureDefinition? structureDefinition;
    if (profile != null && profile.isNotEmpty) {
      structureDefinition = await _resolveProfile(dbInterface, profile);
      if (structureDefinition == null) {
        // The SHALL above: say so rather than validating against the base
        // type and reporting that as the answer.
        return _outcome(
          400,
          'not-supported',
          'Cannot validate against the nominated profile "$profile": no '
              'StructureDefinition with that canonical URL is known to this '
              'server. POST the StructureDefinition first.',
        );
      }
    }
    // With no profile nominated the engine resolves the base type itself,
    // through the cache below, by its canonical URL
    // http://hl7.org/fhir/StructureDefinition/<type>.

    final validator = FhirValidationEngine();
    final ValidationResults validationResults;
    try {
      validationResults = await validator.validateFhirMap(
        structureToValidate: resourceJson,
        structureDefinition: structureDefinition,
        // Every StructureDefinition, ValueSet and CodeSystem the engine needs
        // comes from this server's own database, which spec_loader fills from
        // the packaged specification on first boot. Nothing goes to the
        // network: the device may not have one, and a validation whose answer
        // depended on connectivity would not be reproducible.
        resourceCache:
            dbInterface == null ? null : DbResourceCache(dbInterface),
      );
    } on Exception catch (e) {
      // The engine throws, rather than returning an issue, when a canonical
      // it needs cannot be resolved — most often a value set behind a coded
      // element: "Resource not found at http://hl7.org/fhir/ValueSet/...".
      // Reporting that as a 500 tells the client we crashed, when what
      // actually happened is that this server cannot answer the question.
      //
      // With fhir_r4_validation 0.12.0 the cache above is this server's own
      // database, so this now means the canonical genuinely is not stored
      // here: an IG profile nobody POSTed, or a value set outside the
      // packaged specification. POST it and the validation completes.
      final message = e.toString();
      if (message.contains('Resource not found at')) {
        return _outcome(
          422,
          'not-supported',
          'Validation needs a canonical resource this server cannot resolve: '
              '$message',
        );
      }
      rethrow;
    }

    final operationOutcome = validationResults.toOperationOutcome();

    if (validationResults.hasErrors) {
      final errorCount = validationResults.results
          .where((r) => r.severity == Severity.error)
          .length;
      FhirantLogging().logWarning(
        'FHIR validation failed with $errorCount errors',
      );
      return Response(
        400,
        body: operationOutcome.toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    }
    FhirantLogging().logInfo('FHIR validation passed');
    return Response.ok(
      operationOutcome.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Validation failed due to an exception',
      e,
      stackTrace,
    );
    return _outcome(500, 'exception', 'Validation error');
  }
}

/// Finds the StructureDefinition a canonical URL names.
///
/// A canonical may carry a version after `|`, which is matched against
/// `StructureDefinition.version` when present. The lookup runs through the
/// ordinary search engine, so a profile POSTed to this server resolves
/// exactly like one loaded from the packaged specification.
Future<fhir.StructureDefinition?> _resolveProfile(
  FhirAntDb? dbInterface,
  String canonical,
) async {
  if (dbInterface == null) return null;

  final pipe = canonical.indexOf('|');
  final url = pipe < 0 ? canonical : canonical.substring(0, pipe);
  final version = pipe < 0 ? null : canonical.substring(pipe + 1);

  final matches = await dbInterface.search(
    resourceType: fhir.R4ResourceType.StructureDefinition,
    searchParameters: {
      'url': [url],
    },
  );

  for (final match in matches.whereType<fhir.StructureDefinition>()) {
    if (version == null || match.version?.valueString == version) {
      return match;
    }
  }
  return null;
}

Response _outcome(int status, String code, String diagnostics) => Response(
      status,
      body: jsonEncode({
        'resourceType': 'OperationOutcome',
        'issue': [
          {
            'severity': 'error',
            'code': code,
            'diagnostics': diagnostics,
          },
        ],
      }),
      headers: {'Content-Type': 'application/json'},
    );
