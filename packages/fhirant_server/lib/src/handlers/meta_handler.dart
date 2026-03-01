import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:shelf/shelf.dart';

/// Handler for $meta operation: GET /{resourceType}/{id}/$meta
///
/// Returns a Parameters resource containing the meta (tags, profiles,
/// security labels) for the specified resource instance.
Future<Response> metaHandler(
  Request request,
  String resourceType,
  String id,
  FhirAntDb dbInterface,
) async {
  try {
    final type = fhir.R4ResourceType.fromString(resourceType);
    if (type == null) {
      return _validationErrorResponse('Invalid resource type');
    }

    final resource = await dbInterface.getResource(type, id);
    if (resource == null) {
      return Response(
        404,
        body: jsonEncode({'error': 'Resource not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Return a Parameters resource with the meta
    final meta = resource.meta ?? const fhir.FhirMeta();
    final parameters = fhir.Parameters(
      parameter: [
        fhir.ParametersParameter(
          name: 'return'.toFhirString,
          valueMeta: meta,
        ),
      ],
    );

    return Response.ok(
      parameters.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error in \$meta for $resourceType/$id',
      e,
      stackTrace,
    );
    return _errorResponse('Failed to get resource meta', e.toString());
  }
}

/// Handler for $meta-add operation: POST /{resourceType}/{id}/$meta-add
///
/// Adds tags, profiles, and/or security labels to a resource's meta.
/// Request body is a Parameters resource with a 'meta' parameter.
Future<Response> metaAddHandler(
  Request request,
  String resourceType,
  String id,
  FhirAntDb dbInterface,
) async {
  try {
    final type = fhir.R4ResourceType.fromString(resourceType);
    if (type == null) {
      return _validationErrorResponse('Invalid resource type');
    }

    final resource = await dbInterface.getResource(type, id);
    if (resource == null) {
      return Response(
        404,
        body: jsonEncode({'error': 'Resource not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Parse the input Parameters resource
    final body = await request.readAsString();
    final inputMeta = _extractMetaFromParameters(body);
    if (inputMeta == null) {
      return _validationErrorResponse(
        'Request body must be a Parameters resource with a meta parameter',
      );
    }

    // Merge: add new tags/profiles/security to existing meta
    final existingMeta = resource.meta ?? const fhir.FhirMeta();
    final mergedMeta = _mergeMeta(existingMeta, inputMeta);

    // Update the resource with new meta (via JSON round-trip)
    final updatedResource = _setMeta(resource, mergedMeta);
    await dbInterface.saveResource(updatedResource);

    // Return the updated meta
    final parameters = fhir.Parameters(
      parameter: [
        fhir.ParametersParameter(
          name: 'return'.toFhirString,
          valueMeta: mergedMeta,
        ),
      ],
    );

    return Response.ok(
      parameters.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error in \$meta-add for $resourceType/$id',
      e,
      stackTrace,
    );
    return _errorResponse('Failed to add resource meta', e.toString());
  }
}

/// Handler for $meta-delete operation: POST /{resourceType}/{id}/$meta-delete
///
/// Removes tags, profiles, and/or security labels from a resource's meta.
/// Request body is a Parameters resource with a 'meta' parameter.
Future<Response> metaDeleteHandler(
  Request request,
  String resourceType,
  String id,
  FhirAntDb dbInterface,
) async {
  try {
    final type = fhir.R4ResourceType.fromString(resourceType);
    if (type == null) {
      return _validationErrorResponse('Invalid resource type');
    }

    final resource = await dbInterface.getResource(type, id);
    if (resource == null) {
      return Response(
        404,
        body: jsonEncode({'error': 'Resource not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Parse the input Parameters resource
    final body = await request.readAsString();
    final inputMeta = _extractMetaFromParameters(body);
    if (inputMeta == null) {
      return _validationErrorResponse(
        'Request body must be a Parameters resource with a meta parameter',
      );
    }

    // Remove: subtract input tags/profiles/security from existing meta
    final existingMeta = resource.meta ?? const fhir.FhirMeta();
    final reducedMeta = _subtractMeta(existingMeta, inputMeta);

    // Update the resource with reduced meta (via JSON round-trip)
    final updatedResource = _setMeta(resource, reducedMeta);
    await dbInterface.saveResource(updatedResource);

    // Return the updated meta
    final parameters = fhir.Parameters(
      parameter: [
        fhir.ParametersParameter(
          name: 'return'.toFhirString,
          valueMeta: reducedMeta,
        ),
      ],
    );

    return Response.ok(
      parameters.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error in \$meta-delete for $resourceType/$id',
      e,
      stackTrace,
    );
    return _errorResponse('Failed to delete resource meta', e.toString());
  }
}

/// Extract a FhirMeta from a Parameters resource body.
fhir.FhirMeta? _extractMetaFromParameters(String body) {
  try {
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (json['resourceType'] != 'Parameters') return null;
    final params = json['parameter'] as List?;
    if (params == null || params.isEmpty) return null;

    for (final param in params) {
      final paramMap = param as Map<String, dynamic>;
      if (paramMap['name'] == 'meta' && paramMap.containsKey('valueMeta')) {
        return fhir.FhirMeta.fromJson(
          paramMap['valueMeta'] as Map<String, dynamic>,
        );
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// Merge new meta elements into existing meta (add operation).
fhir.FhirMeta _mergeMeta(fhir.FhirMeta existing, fhir.FhirMeta toAdd) {
  // Merge profiles (deduplicate by URI)
  final existingProfiles =
      existing.profile?.map((p) => p.toString()).toSet() ?? <String>{};
  final newProfiles = <fhir.FhirCanonical>[
    ...?existing.profile,
    ...?(toAdd.profile
        ?.where((p) => !existingProfiles.contains(p.toString()))
        .toList()),
  ];

  // Merge tags (deduplicate by system+code)
  final existingTagKeys = existing.tag
          ?.map((t) => '${t.system}|${t.code}')
          .toSet() ??
      <String>{};
  final newTags = <fhir.Coding>[
    ...?existing.tag,
    ...?(toAdd.tag
        ?.where(
            (t) => !existingTagKeys.contains('${t.system}|${t.code}'))
        .toList()),
  ];

  // Merge security labels (deduplicate by system+code)
  final existingSecKeys = existing.security
          ?.map((s) => '${s.system}|${s.code}')
          .toSet() ??
      <String>{};
  final newSecurity = <fhir.Coding>[
    ...?existing.security,
    ...?(toAdd.security
        ?.where(
            (s) => !existingSecKeys.contains('${s.system}|${s.code}'))
        .toList()),
  ];

  return existing.copyWith(
    profile: newProfiles.isEmpty ? null : newProfiles,
    tag: newTags.isEmpty ? null : newTags,
    security: newSecurity.isEmpty ? null : newSecurity,
  );
}

/// Remove meta elements from existing meta (delete operation).
fhir.FhirMeta _subtractMeta(
    fhir.FhirMeta existing, fhir.FhirMeta toRemove) {
  // Remove profiles by URI
  final removeProfiles =
      toRemove.profile?.map((p) => p.toString()).toSet() ?? <String>{};
  final remainingProfiles = existing.profile
      ?.where((p) => !removeProfiles.contains(p.toString()))
      .toList();

  // Remove tags by system+code
  final removeTagKeys = toRemove.tag
          ?.map((t) => '${t.system}|${t.code}')
          .toSet() ??
      <String>{};
  final remainingTags = existing.tag
      ?.where((t) => !removeTagKeys.contains('${t.system}|${t.code}'))
      .toList();

  // Remove security labels by system+code
  final removeSecKeys = toRemove.security
          ?.map((s) => '${s.system}|${s.code}')
          .toSet() ??
      <String>{};
  final remainingSecurity = existing.security
      ?.where((s) => !removeSecKeys.contains('${s.system}|${s.code}'))
      .toList();

  return existing.copyWith(
    profile: remainingProfiles == null || remainingProfiles.isEmpty
        ? null
        : remainingProfiles,
    tag: remainingTags == null || remainingTags.isEmpty
        ? null
        : remainingTags,
    security: remainingSecurity == null || remainingSecurity.isEmpty
        ? null
        : remainingSecurity,
  );
}

/// Set meta on a resource via JSON round-trip.
/// This avoids the type-specific copyWith pattern and does not increment
/// version or lastUpdated (that is handled by saveResource).
fhir.Resource _setMeta(fhir.Resource resource, fhir.FhirMeta meta) {
  final json = resource.toJson();
  json['meta'] = meta.toJson();
  return fhir.Resource.fromJson(json);
}

Response _errorResponse(String message, String details,
    {int statusCode = 500}) {
  final operationOutcome = fhir.OperationOutcome(
    issue: [
      fhir.OperationOutcomeIssue(
        severity: fhir.IssueSeverity.error,
        code: fhir.IssueType.exception,
        diagnostics: '$message: $details'.toFhirString,
      ),
    ],
  );
  return Response(
    statusCode,
    body: operationOutcome.toJsonString(),
    headers: {'Content-Type': 'application/json'},
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
  return Response(
    400,
    body: operationOutcome.toJsonString(),
    headers: {'Content-Type': 'application/json'},
  );
}
