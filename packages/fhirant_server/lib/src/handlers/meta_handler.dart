import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/services/subscription_service.dart';
import 'package:fhirant_server/src/utils/operation_outcomes.dart';
import 'package:fhirant_server/src/utils/stored_resource.dart';
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
    final lookup = await lookupStored(
      request,
      dbInterface,
      resourceType,
      id,
      permission: 'r',
    );
    if (lookup is! StoredFound) return lookupRefusal(lookup);
    final resource = lookup.resource;

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
      'Error in \$meta for $resourceType/{id}',
      e,
      stackTrace,
    );
    return exceptionOutcome('Failed to get resource meta', 'Internal error');
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
  FhirAntDb dbInterface, {
  SubscriptionService? subscriptions,
}) async {
  // A new version of the resource: its subscribers are notified, as after
  // a PUT (REVIEW-2026-09-17 A7).
  final subs = subscriptions ?? SubscriptionService(dbInterface);
  try {
    final lookup = await lookupStored(
      request,
      dbInterface,
      resourceType,
      id,
      permission: 'u',
    );
    if (lookup is! StoredFound) return lookupRefusal(lookup);
    final resource = lookup.resource;

    // Parse the input Parameters resource
    final body = await request.readAsString();
    final inputMeta = _extractMetaFromParameters(body);
    if (inputMeta == null) {
      return validationOutcome(
        'Request body must be a Parameters resource with a meta parameter',
      );
    }

    // Merge: add new tags/profiles/security to existing meta
    final existingMeta = resource.meta ?? const fhir.FhirMeta();
    final mergedMeta = _mergeMeta(existingMeta, inputMeta);

    // Update the resource with new meta (via JSON round-trip)
    final updatedResource = _setMeta(resource, mergedMeta);
    final saved = await dbInterface.saveResource(updatedResource);
    await subs.onResourceChanged(saved);

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
      'Error in \$meta-add for $resourceType/{id}',
      e,
      stackTrace,
    );
    return exceptionOutcome('Failed to add resource meta', 'Internal error');
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
  FhirAntDb dbInterface, {
  SubscriptionService? subscriptions,
}) async {
  final subs = subscriptions ?? SubscriptionService(dbInterface);
  try {
    final lookup = await lookupStored(
      request,
      dbInterface,
      resourceType,
      id,
      permission: 'u',
    );
    if (lookup is! StoredFound) return lookupRefusal(lookup);
    final resource = lookup.resource;

    // Parse the input Parameters resource
    final body = await request.readAsString();
    final inputMeta = _extractMetaFromParameters(body);
    if (inputMeta == null) {
      return validationOutcome(
        'Request body must be a Parameters resource with a meta parameter',
      );
    }

    // Remove: subtract input tags/profiles/security from existing meta
    final existingMeta = resource.meta ?? const fhir.FhirMeta();
    final reducedMeta = _subtractMeta(existingMeta, inputMeta);

    // Update the resource with reduced meta (via JSON round-trip). The store
    // merges stored tags and security labels into a save by default
    // (resource.html 2.26.3.9); this save must write exactly what is left.
    final updatedResource = _setMeta(resource, reducedMeta);
    final saved = await dbInterface.saveResource(
      updatedResource,
      mergeTags: false,
    );
    await subs.onResourceChanged(saved);

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
      'Error in \$meta-delete for $resourceType/{id}',
      e,
      stackTrace,
    );
    return exceptionOutcome('Failed to delete resource meta', 'Internal error');
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
  } on FormatException {
    // Not JSON: no meta parameter, and the caller's 400 says a Parameters
    // resource is required. Anything else propagates; this used to swallow
    // every failure as "no meta".
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
  final existingTagKeys =
      existing.tag?.map((t) => '${t.system}|${t.code}').toSet() ?? <String>{};
  final newTags = <fhir.Coding>[
    ...?existing.tag,
    ...?(toAdd.tag
        ?.where((t) => !existingTagKeys.contains('${t.system}|${t.code}'))
        .toList()),
  ];

  // Merge security labels (deduplicate by system+code)
  final existingSecKeys =
      existing.security?.map((s) => '${s.system}|${s.code}').toSet() ??
          <String>{};
  final newSecurity = <fhir.Coding>[
    ...?existing.security,
    ...?(toAdd.security
        ?.where((s) => !existingSecKeys.contains('${s.system}|${s.code}'))
        .toList()),
  ];

  return existing.copyWith(
    profile: newProfiles.isEmpty ? null : newProfiles,
    tag: newTags.isEmpty ? null : newTags,
    security: newSecurity.isEmpty ? null : newSecurity,
  );
}

/// Remove meta elements from existing meta (delete operation).
fhir.FhirMeta _subtractMeta(fhir.FhirMeta existing, fhir.FhirMeta toRemove) {
  // Remove profiles by URI
  final removeProfiles =
      toRemove.profile?.map((p) => p.toString()).toSet() ?? <String>{};
  final remainingProfiles = existing.profile
      ?.where((p) => !removeProfiles.contains(p.toString()))
      .toList();

  // Remove tags by system+code
  final removeTagKeys =
      toRemove.tag?.map((t) => '${t.system}|${t.code}').toSet() ?? <String>{};
  final remainingTags = existing.tag
      ?.where((t) => !removeTagKeys.contains('${t.system}|${t.code}'))
      .toList();

  // Remove security labels by system+code
  final removeSecKeys =
      toRemove.security?.map((s) => '${s.system}|${s.code}').toSet() ??
          <String>{};
  final remainingSecurity = existing.security
      ?.where((s) => !removeSecKeys.contains('${s.system}|${s.code}'))
      .toList();

  return existing.copyWith(
    profile: remainingProfiles == null || remainingProfiles.isEmpty
        ? null
        : remainingProfiles,
    tag: remainingTags == null || remainingTags.isEmpty ? null : remainingTags,
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
