import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/auth/request_authorization.dart';
import 'package:fhirant_server/src/utils/http_headers.dart';
import 'package:fhirant_server/src/utils/operation_outcomes.dart';
import 'package:fhirant_server/src/utils/patient_scope.dart';
import 'package:fhirant_server/src/utils/search_links.dart';
import 'package:fhirant_server/src/utils/search_page.dart';
import 'package:fhirant_server/src/utils/search_parser.dart';
import 'package:shelf/shelf.dart';

/// Handler for resource-level history: GET /{resourceType}/{id}/_history
Future<Response> resourceHistoryHandler(
  Request request,
  String resourceType,
  String id,
  FhirAntDb dbInterface,
) async {
  try {
    FhirantLogging().logInfo(
      'Fetching history for resource: $resourceType/{id}',
    );

    final type = fhir.R4ResourceType.fromString(resourceType);
    if (type == null) {
      FhirantLogging().logWarning(
        'Invalid resource type requested: $resourceType',
      );
      return validationOutcome('Invalid resource type');
    }

    // Get pagination and history parameters
    final repeatError = _repeatedError(request.url.queryParametersAll);
    if (repeatError != null) return validationOutcome(repeatError);
    final queryParams = request.url.queryParameters;
    final pageError = pageArgumentError(
      queryParams['_count'],
      queryParams['_offset'],
    );
    if (pageError != null) return validationOutcome(pageError);
    final count = pageSize(queryParams['_count']);
    final offset = int.parse(queryParams['_offset'] ?? '0');
    final since = _parseSince(queryParams['_since']);
    final at = _parseSince(queryParams['_at']);
    final instantError = _instantError(queryParams, since, at);
    if (instantError != null) return validationOutcome(instantError);

    // _since and _at are mutually exclusive
    if (since != null && at != null) {
      return validationOutcome(
        '_since and _at are mutually exclusive; specify only one',
      );
    }

    // The compartment, as a read of the resource applies it: a patient
    // token read any resource's versions (REVIEW-2026-09-08 row 4).
    final outside =
        await _refuseOutsideCompartment(request, resourceType, id, dbInterface);
    if (outside != null) return outside;

    // Get history from database (with optional _since or _at filter)
    final total = await dbInterface.countHistory(
      type,
      id,
      since: since,
      at: at,
    );
    final paginatedHistory = total == 0
        ? const <HistoryEntry>[]
        : await dbInterface.getHistory(
            type,
            id,
            since: since,
            at: at,
            count: count,
            offset: offset,
          );

    if (total == 0) {
      FhirantLogging().logWarning(
        'No history found for resource: $resourceType/{id}',
      );
      return notFoundOutcome('$resourceType/{id}');
    }

    // Build base URL
    final baseUrl = baseUrlOf(request.requestedUri);

    // Create Bundle with history entries, paged with the links of
    // http.html §3.1.0.14.
    final bundle = fhir.Bundle(
      type: fhir.BundleType.history,
      entry: [
        for (final e in paginatedHistory) _historyEntry(e, baseUrl),
      ],
      total: fhir.FhirUnsignedInt(total),
      link: SearchLinks.history(request.url.queryParametersAll).page(
        request.requestedUri,
        count: count,
        offset: offset,
        total: total,
      ),
    );

    FhirantLogging().logInfo(
      'Successfully fetched ${paginatedHistory.length} history entries '
      'for resource: $resourceType/{id}',
    );

    return Response.ok(
      bundle.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error fetching history for resource: $resourceType/{id}',
      e,
      stackTrace,
    );
    return exceptionOutcome(
      'Failed to fetch resource history',
      'Internal error',
    );
  }
}

/// Handler for type-level history: GET /{resourceType}/_history
Future<Response> typeHistoryHandler(
  Request request,
  String resourceType,
  FhirAntDb dbInterface,
) async {
  try {
    FhirantLogging().logInfo(
      'Fetching history for resource type: $resourceType',
    );

    final type = fhir.R4ResourceType.fromString(resourceType);
    if (type == null) {
      FhirantLogging().logWarning(
        'Invalid resource type requested: $resourceType',
      );
      return validationOutcome('Invalid resource type');
    }

    // Get pagination and history parameters
    final repeatError = _repeatedError(request.url.queryParametersAll);
    if (repeatError != null) return validationOutcome(repeatError);
    final queryParams = request.url.queryParameters;
    final pageError = pageArgumentError(
      queryParams['_count'],
      queryParams['_offset'],
    );
    if (pageError != null) return validationOutcome(pageError);
    final count = pageSize(queryParams['_count']);
    final offset = int.parse(queryParams['_offset'] ?? '0');
    final since = _parseSince(queryParams['_since']);
    final at = _parseSince(queryParams['_at']);
    final instantError = _instantError(queryParams, since, at);
    if (instantError != null) return validationOutcome(instantError);

    // _since and _at are mutually exclusive
    if (since != null && at != null) {
      return validationOutcome(
        '_since and _at are mutually exclusive; specify only one',
      );
    }

    // The page and the total come from SQL (REVIEW-2026-09-06 finding 36),
    // inside the token's compartment when it has one for this type
    // (REVIEW-2026-09-08 row 4).
    final compartment =
        Principal.of(request)?.compartmentFor(resourceType, 'r');
    final position = _position(queryParams, at: at, compartment: compartment);
    if (position.error != null) return validationOutcome(position.error!);
    final after = position.after;
    final keyed = position.keyed;
    final total = after != null
        ? null
        : await dbInterface.countTypeHistory(
            type,
            since: since,
            at: at,
            compartment: compartment,
          );
    final rows = await dbInterface.getTypeHistory(
      type,
      since: since,
      at: at,
      count: keyed ? count + 1 : count,
      offset: after == null ? offset : null,
      after: after,
      compartment: compartment,
    );
    final more = keyed && rows.length > count;
    final paginatedHistory = more ? rows.sublist(0, count) : rows;

    // Build base URL
    final baseUrl = baseUrlOf(request.requestedUri);

    // Create Bundle with history entries, paged with the links of
    // http.html §3.1.0.14.
    final bundle = fhir.Bundle(
      type: fhir.BundleType.history,
      entry: [
        for (final e in paginatedHistory) _historyEntry(e, baseUrl),
      ],
      total: total == null ? null : fhir.FhirUnsignedInt(total),
      link: SearchLinks.history(request.url.queryParametersAll).page(
        request.requestedUri,
        count: count,
        offset: after == null ? offset : 0,
        total: total,
        hasMore: keyed ? more : null,
        nextCursor: keyed && paginatedHistory.isNotEmpty
            ? _cursorOf(paginatedHistory.last)
            : null,
      ),
    );

    FhirantLogging().logInfo(
      'Successfully fetched ${paginatedHistory.length} history entries '
      'for resource type: $resourceType',
    );

    return Response.ok(
      bundle.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error fetching history for resource type: $resourceType',
      e,
      stackTrace,
    );
    return exceptionOutcome(
      'Failed to fetch resource type history',
      'Internal error',
    );
  }
}

/// Handler for system-level history: GET /_history
Future<Response> systemHistoryHandler(
  Request request,
  FhirAntDb dbInterface,
) async {
  try {
    FhirantLogging().logInfo('Fetching system-level history');

    // Get pagination and history parameters
    final repeatError = _repeatedError(request.url.queryParametersAll);
    if (repeatError != null) return validationOutcome(repeatError);
    final queryParams = request.url.queryParameters;
    final pageError = pageArgumentError(
      queryParams['_count'],
      queryParams['_offset'],
    );
    if (pageError != null) return validationOutcome(pageError);
    final count = pageSize(queryParams['_count']);
    final offset = int.parse(queryParams['_offset'] ?? '0');
    final since = _parseSince(queryParams['_since']);
    final at = _parseSince(queryParams['_at']);
    final instantError = _instantError(queryParams, since, at);
    if (instantError != null) return validationOutcome(instantError);

    // _since and _at are mutually exclusive
    if (since != null && at != null) {
      return validationOutcome(
        '_since and _at are mutually exclusive; specify only one',
      );
    }

    // The page and the total come from SQL (REVIEW-2026-09-06 finding 36).
    // System history names no type, so the middleware checked no scope: a
    // caller with a patient context is confined to its compartment across
    // every type, and any other caller needs a read on every type, as the
    // root data operations do (REVIEW-2026-09-08 row 4).
    final principal = Principal.of(request);
    CompartmentScope? compartment;
    if (principal != null) {
      compartment = principal.compartmentFor('Patient', 'r');
      if (compartment == null && !principal.mayReadUnscoped) {
        return forbidden(
          'System history returns every resource type, so it requires a '
          'user- or system-context scope covering all resource types.',
        );
      }
    }
    final position = _position(queryParams, at: at, compartment: compartment);
    if (position.error != null) return validationOutcome(position.error!);
    final after = position.after;
    final keyed = position.keyed;
    final total = after != null
        ? null
        : await dbInterface.countSystemHistory(
            since: since,
            at: at,
            compartment: compartment,
          );
    final rows = await dbInterface.getSystemHistory(
      since: since,
      at: at,
      count: keyed ? count + 1 : count,
      offset: after == null ? offset : null,
      after: after,
      compartment: compartment,
    );
    final more = keyed && rows.length > count;
    final paginatedHistory = more ? rows.sublist(0, count) : rows;

    // Build base URL
    final baseUrl = baseUrlOf(request.requestedUri);

    // Create Bundle with history entries, paged with the links of
    // http.html §3.1.0.14.
    final bundle = fhir.Bundle(
      type: fhir.BundleType.history,
      entry: [
        for (final e in paginatedHistory) _historyEntry(e, baseUrl),
      ],
      total: total == null ? null : fhir.FhirUnsignedInt(total),
      link: SearchLinks.history(request.url.queryParametersAll).page(
        request.requestedUri,
        count: count,
        offset: after == null ? offset : 0,
        total: total,
        hasMore: keyed ? more : null,
        nextCursor: keyed && paginatedHistory.isNotEmpty
            ? _cursorOf(paginatedHistory.last)
            : null,
      ),
    );

    FhirantLogging().logInfo(
      'Successfully fetched ${paginatedHistory.length} '
      'system-level history entries',
    );

    return Response.ok(
      bundle.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error fetching system-level history',
      e,
      stackTrace,
    );
    return exceptionOutcome(
      'Failed to fetch system history',
      'Internal error',
    );
  }
}

/// Handler for version-specific read (VRead): GET /{resourceType}/{id}/_history/{vid}
Future<Response> vreadResourceHandler(
  Request request,
  String resourceType,
  String id,
  String vid,
  FhirAntDb dbInterface,
) async {
  try {
    FhirantLogging().logInfo(
      'Fetching version {vid} of resource: $resourceType/{id}',
    );

    final type = fhir.R4ResourceType.fromString(resourceType);
    if (type == null) {
      FhirantLogging().logWarning(
        'Invalid resource type requested: $resourceType',
      );
      return validationOutcome('Invalid resource type');
    }

    final outside =
        await _refuseOutsideCompartment(request, resourceType, id, dbInterface);
    if (outside != null) return outside;

    // One row by its key (REVIEW-2026-09-06 finding 36: every version used
    // to be read to find one).
    final entry = await dbInterface.getVersion(type, id, vid);
    if (entry == null) {
      final any = await dbInterface.countHistory(type, id);
      FhirantLogging().logWarning(
        any == 0
            ? 'No history found for resource: $resourceType/{id}'
            : 'Version $vid not found for resource: $resourceType/{id}',
      );
      return notFoundOutcome(
        any == 0 ? '$resourceType/{id}' : '$resourceType/{id}/_history/$vid',
      );
    }

    // A deletion tombstone is 410, not a resource
    if (entry.deleted) {
      FhirantLogging().logInfo(
        'Version {vid} of $resourceType/{id} is a deletion tombstone (410)',
      );
      return Response(
        410,
        body: fhir.OperationOutcome(
          issue: [
            fhir.OperationOutcomeIssue(
              severity: fhir.IssueSeverity.error,
              code: fhir.IssueType.deleted,
              diagnostics:
                  'Resource $resourceType/{id} version $vid has been deleted'
                      .toFhirString,
            ),
          ],
        ).toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    }
    final versionedResource = entry.resource!;

    FhirantLogging().logInfo(
      'Successfully fetched version {vid} of resource: $resourceType/{id}',
    );

    return Response.ok(
      versionedResource.toJsonString(),
      headers: FhirHttpHeaders.resourceHeaders(versionedResource),
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error fetching version {vid} of resource: $resourceType/{id}',
      e,
      stackTrace,
    );
    return exceptionOutcome(
      'Failed to fetch resource version',
      'Internal error',
    );
  }
}

/// A 403 when the caller's read of [resourceType] is confined to a patient
/// compartment and `[resourceType]/[id]` is not a current member of it, or
/// null. A resource that no longer exists has no index rows to prove
/// membership by, so its history is refused to a confined caller.
Future<Response?> _refuseOutsideCompartment(
  Request request,
  String resourceType,
  String id,
  FhirAntDb dbInterface,
) async {
  final patientId = patientContextFor(request, resourceType, 'r');
  if (patientId == null) return null;
  if (await isInPatientCompartment(resourceType, id, patientId, dbInterface)) {
    return null;
  }
  // As absent: a read (REVIEW-2026-09-17 A13).
  return patientScopeNotFoundResponse(resourceType, id);
}

/// R4B http.html 3.1.0.10 (read 2026-10-20, verbatim), after the table of
/// history parameters: "Each of these parameters SHALL NOT appear more than
/// once." A request that repeats one is refused rather than answered with
/// one value applied and both in the self link (REVIEW-2026-10-17).
String? _repeatedError(Map<String, List<String>> query) {
  for (final name in const [
    '_count',
    '_since',
    '_at',
    '_list',
    SearchLinks.historyCursor,
  ]) {
    if ((query[name]?.length ?? 0) > 1) {
      return '$name SHALL NOT appear more than once in a history request';
    }
  }
  return null;
}

/// A `_since` or `_at` that was given and did not parse: R4B 3.1.1.3, a
/// syntactically incorrect parameter is an error, not something to ignore
/// (REVIEW-2026-09-08 row 32).
String? _instantError(
  Map<String, String> queryParams,
  DateTime? since,
  DateTime? at,
) {
  for (final (name, parsed) in [('_since', since), ('_at', at)]) {
    final raw = queryParams[name];
    if (raw != null && raw.isNotEmpty && parsed == null) {
      return '$name must be an instant; got "$raw"';
    }
  }
  return null;
}

/// Parse a FHIR instant/dateTime string into a [DateTime].
DateTime? _parseSince(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

/// One `Bundle.entry` of a history Bundle, the same for instance, type and
/// system history. R4B http.html "history" (read 2026-09-07): "Each entry
/// SHALL minimally contain at least one of: a resource which holds the
/// resource as it is at the conclusion of the interaction, or a request with
/// entry.request.method"; "If the entry.request.method is a PUT or a POST,
/// the entry SHALL contain a resource"; its delete example is an entry with
/// no resource, `method DELETE`, `url Patient/[id]` and a response
/// `lastModified`. A tombstone is that entry (status 204). Version 1 is the
/// create (`POST`, url `[type]`, 201); a later version an update (`PUT`,
/// url `[type]/[id]`, 200); under timestamp versioning the first version is
/// not told apart, and every version is a `PUT`, which http.html also
/// allows as a create ("Update as Create"). Type and system history used to
/// emit the tombstone JSON as a `GET` resource (REVIEW-2026-09-06 finding
/// 25).
fhir.BundleEntry _historyEntry(HistoryEntry e, String baseUrl) {
  final path = '${e.resourceType}/${e.id}';
  final isCreate = e.versionId == '1';
  return fhir.BundleEntry(
    resource: e.resource,
    fullUrl: fhir.FhirUri('$baseUrl/$path'),
    request: fhir.BundleRequest(
      method: e.deleted
          ? fhir.HTTPVerb.dELETE
          : isCreate
              ? fhir.HTTPVerb.pOST
              : fhir.HTTPVerb.pUT,
      url: fhir.FhirUri(isCreate && !e.deleted ? e.resourceType : path),
    ),
    response: fhir.BundleResponse(
      status: (e.deleted
              ? '204'
              : isCreate
                  ? '201'
                  : '200')
          .toFhirString,
      // The create's Location, as the create answered it: a history Bundle
      // posted to another server is checked against it (http.html
      // §3.1.0.11.4, "must match the Bundle.entry.response.location").
      location: isCreate && !e.deleted
          ? fhir.FhirUri('$path/_history/${e.versionId}')
          : null,
      etag: 'W/"${e.versionId}"'.toFhirString,
      lastModified: fhir.FhirInstant.fromDateTime(e.lastUpdated),
    ),
  );
}

/// The `_cursor` a type or system history request carries, as the position
/// its page starts after ([SearchLinks.historyCursor]). [keyed] is whether
/// the page is found by position at all: not under `_at` or a compartment,
/// whose pages are counted by offset as before. A cursor this server could
/// not have given, or one with `_offset`, `_at` or a compartment, is an
/// [error] (R4B 3.1.1.3: a parameter in error is not ignored).
({HistoryPosition? after, bool keyed, String? error}) _position(
  Map<String, String> queryParams, {
  required DateTime? at,
  required CompartmentScope? compartment,
}) {
  final keyed = at == null && compartment == null;
  final raw = queryParams[SearchLinks.historyCursor];
  if (raw == null) return (after: null, keyed: keyed, error: null);
  if (!keyed || queryParams['_offset'] != null) {
    return (
      after: null,
      keyed: keyed,
      error: '${SearchLinks.historyCursor} pages history without _offset, '
          '_at or a patient compartment',
    );
  }
  final after = _parseCursor(raw);
  return (
    after: after,
    keyed: keyed,
    error: after == null
        ? '${SearchLinks.historyCursor} is not one this server gives'
        : null,
  );
}

/// The [SearchLinks.historyCursor] value after [e]: its `last_updated` in
/// milliseconds, version id, type and id, joined by `|`, which none of the
/// four can contain (an id and a version id are `[A-Za-z0-9\-\.]{1,64}`,
/// R4B datatypes.html id).
String _cursorOf(HistoryEntry e) =>
    '${e.lastUpdated.millisecondsSinceEpoch}|${e.versionId}|'
    '${e.resourceType}|${e.id}';

final _idPattern = RegExp(r'^[A-Za-z0-9\-\.]{1,64}$');

HistoryPosition? _parseCursor(String raw) {
  final parts = raw.split('|');
  if (parts.length != 4) return null;
  final ms = int.tryParse(parts[0]);
  if (ms == null ||
      !_idPattern.hasMatch(parts[1]) ||
      fhir.R4ResourceType.fromString(parts[2]) == null ||
      !_idPattern.hasMatch(parts[3])) {
    return null;
  }
  return HistoryPosition(
    lastUpdated: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
    versionId: parts[1],
    resourceType: parts[2],
    id: parts[3],
  );
}
