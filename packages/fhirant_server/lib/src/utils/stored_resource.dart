import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/auth/request_authorization.dart';
import 'package:fhirant_server/src/utils/operation_outcomes.dart';
import 'package:fhirant_server/src/utils/patient_scope.dart';
import 'package:shelf/shelf.dart';

/// The one answer to "the resource this URL names, under this caller's
/// scope". Every route that names `[type]/[id]` decides the same three
/// things: is the type real, is the resource there, may this caller reach
/// it. Before 2026-09-22 that decision was written at 17 sites in 7 files,
/// with four private scope helpers and four wordings of the 404; DELETE's
/// not-found carried issue code `exception`.
///
/// Decided in that order: type, then presence, then scope. A patient-scoped
/// READ outside the compartment is answered as an absent resource, for the
/// reason [patientScopeNotFoundResponse] gives with its source.
sealed class StoredLookup {
  const StoredLookup();
}

/// The resource is there and the caller may reach it.
final class StoredFound extends StoredLookup {
  const StoredFound(this.type, this.resource);
  final fhir.R4ResourceType type;
  final fhir.Resource resource;
}

/// `[resourceType]` names no R4 resource type.
final class StoredInvalidType extends StoredLookup {
  const StoredInvalidType(this.resourceType);
  final String resourceType;
}

/// The store holds no current version of `[resourceType]/[id]`.
final class StoredAbsent extends StoredLookup {
  const StoredAbsent(this.resourceType, this.id);
  final String resourceType;
  final String id;
}

/// The resource is there, and the caller's patient scope does not reach
/// it. [permission] is the SMART letter the caller needed (`r`, `u`, `d`).
final class StoredOutsideCompartment extends StoredLookup {
  const StoredOutsideCompartment(
    this.resourceType,
    this.id,
    this.patientId,
    this.permission,
  );
  final String resourceType;
  final String id;
  final String patientId;
  final String permission;
}

/// Looks up `[resourceType]/[id]` for the caller of [request]:
/// [lookupStoredFor] with the request's principal.
Future<StoredLookup> lookupStored(
  Request request,
  FhirAntDb dbInterface,
  String resourceType,
  String id, {
  String? permission,
}) =>
    lookupStoredFor(
      Principal.of(request),
      dbInterface,
      resourceType,
      id,
      permission: permission,
    );

/// Looks up `[resourceType]/[id]` for [principal] (null: no caller scope,
/// as in dev mode).
///
/// With [permission], the caller's patient compartment for that permission
/// on that type is applied ([Principal.compartmentFor]); without it, any
/// resource the store holds is returned, which is right for the
/// terminology, CQL and mapping artefacts that live in no patient
/// compartment. Bundle entries call this form: an entry has no Request of
/// its own, only the Bundle's principal.
Future<StoredLookup> lookupStoredFor(
  Principal? principal,
  FhirAntDb dbInterface,
  String resourceType,
  String id, {
  String? permission,
}) async {
  final type = fhir.R4ResourceType.fromString(resourceType);
  if (type == null) return StoredInvalidType(resourceType);
  final resource = await dbInterface.getResource(type, id);
  if (resource == null) return StoredAbsent(resourceType, id);
  if (permission != null) {
    final patientId = principal?.compartmentFor(resourceType, permission)?.id;
    if (patientId != null &&
        !await isInPatientCompartment(
          resourceType,
          id,
          patientId,
          dbInterface,
        )) {
      return StoredOutsideCompartment(resourceType, id, patientId, permission);
    }
  }
  return StoredFound(type, resource);
}

/// The REST answer to a lookup that did not find a reachable resource:
/// 400 for a type that does not exist, 404 for an absent resource, and for
/// one outside the caller's compartment 404 on a read and 403 on a write.
Response lookupRefusal(StoredLookup lookup) => switch (lookup) {
      StoredFound() => throw StateError('found: nothing to refuse'),
      StoredInvalidType(:final resourceType) =>
        invalidTypeOutcome(resourceType),
      StoredAbsent(:final resourceType, :final id) =>
        notFoundOutcome('$resourceType/$id'),
      StoredOutsideCompartment(
        :final resourceType,
        :final id,
        :final patientId,
        :final permission
      ) =>
        permission == 'r'
            ? patientScopeNotFoundResponse(resourceType, id)
            : patientScopeForbiddenResponse(resourceType, id, patientId),
    };
