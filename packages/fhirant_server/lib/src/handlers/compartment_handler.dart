import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/utils/operation_outcomes.dart';
import 'package:fhirant_server/src/utils/patient_scope.dart';
import 'package:fhirant_server/src/utils/search_links.dart';
import 'package:fhirant_server/src/utils/search_page.dart';
import 'package:fhirant_server/src/utils/search_parser.dart';
import 'package:fhirant_server/src/utils/smart_scopes.dart';
import 'package:fhirant_server/src/utils/stored_resource.dart';
import 'package:shelf/shelf.dart';

/// The token's scopes, or null when no authenticated caller is on the
/// request (a handler test calling this directly). The middleware in front
/// of these routes checks the scope against the COMPARTMENT type, which is
/// the first path segment; what they return is another type, so each
/// handler checks that here (REVIEW-2026-09-06 findings 3 and 4).
List<String>? _scopesOf(Request request) {
  final authUser = request.context['auth_user'] as Map<String, dynamic>?;
  final scopes = authUser?['scopes'];
  return scopes is List ? scopes.cast<String>() : null;
}

/// A patient-scoped token may use these routes only on ITS OWN Patient
/// compartment. Another patient's compartment is refused; so is a
/// non-Patient compartment (`Encounter/x/...`), because the store applies
/// one compartment per search and could not also confine the result to
/// the patient.
Response? _refuseOutsidePatientContext(
  Request request,
  String compartmentType,
  String compartmentId,
  String resourceType,
  String permission,
) {
  final patientId = patientContextFor(request, resourceType, permission);
  if (patientId == null) return null;
  if (compartmentType == 'Patient' && compartmentId == patientId) return null;
  // As absent: the same answer the focal resource's absence gives below
  // (REVIEW-2026-09-17 A13; R4B security.html's 404).
  return outcome(
    404,
    fhir.IssueType.notFound,
    '$compartmentType/$compartmentId not found',
  );
}

/// The compartments this server answers `$everything` and compartment
/// searches for: the published CompartmentDefinitions, as generated into
/// fhir_r4_db.
Iterable<String> get supportedCompartments => compartmentDefinitions.keys;

/// Handler for `GET /<compartmentType>/<id>/$everything`.
///
/// Returns a searchset Bundle containing the focal resource plus every
/// resource in its compartment (compartmentdefinition.html), optionally
/// restricted by `_type` and `_since`, paged by `_count`/`_offset`.
Future<Response> everythingHandler(
  Request request,
  String compartmentType,
  String id,
  FhirAntDb dbInterface,
) async {
  try {
    // 1. Validate compartment type
    if (!compartmentDefinitions.containsKey(compartmentType)) {
      return outcome(
        400,
        fhir.IssueType.processing,
        'Unsupported compartment type: $compartmentType. '
        'Supported types: ${supportedCompartments.join(', ')}',
      );
    }

    // 2. Fetch focal resource
    final outside = _refuseOutsidePatientContext(
      request,
      compartmentType,
      id,
      compartmentType,
      'r',
    );
    if (outside != null) return outside;
    final lookup =
        await lookupStored(request, dbInterface, compartmentType, id);
    if (lookup is! StoredFound) return lookupRefusal(lookup);
    final focalResource = lookup.resource;

    // 3. Parse optional parameters
    final queryParams = request.url.queryParameters;
    final typeFilterParam = queryParams['_type'];
    final sinceParam = queryParams['_since'];
    final countParam = queryParams['_count'];
    final offsetParam = queryParams['_offset'];

    final typeFilter =
        typeFilterParam?.split(',').map((s) => s.trim()).toList();
    DateTime? since;
    if (sinceParam != null) {
      since = DateTime.tryParse(sinceParam);
      // R4B 3.1.1.3: "Where the content of the parameter is syntactically
      // incorrect, servers SHOULD return an error." A `_since` that was not
      // an instant used to be ignored, and everything returned
      // (REVIEW-2026-09-08 row 32).
      if (since == null) {
        return outcome(
          400,
          fhir.IssueType.invalid,
          '_since must be an instant; got "$sinceParam"',
        );
      }
    }
    final pageError = pageArgumentError(countParam, offsetParam);
    if (pageError != null) {
      return outcome(400, fhir.IssueType.invalid, pageError);
    }
    final count = pageSize(countParam, defaultCount: 100);
    final offset = int.parse(offsetParam ?? '0');

    // 4. Every member of the compartment, by type, from the reference index.
    // The focal resource is always first. OperationDefinition
    // Patient-everything: "At a minimum, the patient resource(s) itself is
    // returned, along with any other resources that the server has that are
    // related to the patient(s)"; `_since`: "Resources updated after this
    // period will be included in the response."; `_type`: "In the absence of
    // any specified types, the server returns all resource types".
    final members = await dbInterface.compartmentMembers(
      CompartmentScope(compartmentType, id),
      types: typeFilter,
      since: since,
    );

    // The token must be able to read every type it is about to be handed.
    // Omitting the types it may not read would answer "$everything" with
    // something less and say nothing; refusing names the types, and `_type`
    // narrows the request.
    final scopes = _scopesOf(request);
    if (scopes != null) {
      final unreadable = {compartmentType, ...members.keys}
          .where((t) => !SmartScopeEnforcer.isAuthorized(scopes, t, 'r'))
          .toList()
        ..sort();
      if (unreadable.isNotEmpty) {
        return outcome(
          403,
          fhir.IssueType.forbidden,
          'Insufficient scope to read ${unreadable.join(', ')}; narrow the '
          'request with _type or obtain a scope covering them.',
        );
      }
    }

    // 5. The page, cut from the ordered (type, id) list BEFORE anything is
    // read: the focal resource at position 0, then each type in name order
    // with its ids sorted. Only the page's resources are hydrated; the
    // total is the member count. This used to read every member of the
    // compartment and then skip to the page, so a patient's whole record
    // was decoded to answer for its first hundred resources
    // (REVIEW-2026-09-06 finding 35).
    final pageIds = <(fhir.R4ResourceType, String)>[];
    var position = 1;
    final types = members.keys.toList()..sort();
    for (final typeName in types) {
      final resTypeEnum = fhir.R4ResourceType.fromString(typeName);
      if (resTypeEnum == null) continue;
      final ids = members[typeName]!
          .where((r) => !(typeName == compartmentType && r == id))
          .toList()
        ..sort();
      for (final resId in ids) {
        if (position >= offset && position < offset + count) {
          pageIds.add((resTypeEnum, resId));
        }
        position++;
      }
    }
    final total = position;
    final paged = <fhir.Resource>[
      if (offset == 0 && count > 0) focalResource,
    ];
    // One `IN (...)` read per type on the page, in the page's order, rather
    // than one read per resource (REVIEW-2026-09-08 row 43).
    final idsByType = <fhir.R4ResourceType, List<String>>{};
    for (final (resTypeEnum, resId) in pageIds) {
      (idsByType[resTypeEnum] ??= []).add(resId);
    }
    for (final entry in idsByType.entries) {
      final byId = {
        for (final r in await dbInterface.getResources(entry.key, entry.value))
          r.id?.toString(): r,
      };
      for (final resId in entry.value) {
        final resource = byId[resId];
        if (resource != null) paged.add(resource);
      }
    }

    // 6. The page, its links and its total, as any search's.
    final bundle = searchsetPage(
      requested: request.requestedUri,
      links: SearchLinks.everything(request.url.queryParametersAll),
      matches: paged,
      count: count,
      offset: offset,
      hasMore: count > 0 && offset + count < total,
      total: queryParams['_total'] == 'none' ? null : total,
    );
    FhirantLogging().logInfo(
      '\$everything for $compartmentType/{id}: $total resources, '
      '${paged.length} on this page',
    );
    return Response.ok(
      bundle.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error in \$everything for $compartmentType/{id}',
      e,
      stackTrace,
    );
    return outcome(500, fhir.IssueType.processing, 'Internal error');
  }
}

/// Handler for `GET /<compartmentType>/<compartmentId>/<resourceType>`.
///
/// R4B search.html 3.1.1.2, the compartment context: a search over the
/// resources of [resourceType] in the compartment of
/// `[compartmentType]/[compartmentId]`, ANDed with the query. The store runs
/// it as one search with a `CompartmentScope`, so it pages, sorts and counts
/// like a type-level search; this handler used to fetch every id in the
/// compartment and pass the list back in as `_id`, and reported the size of
/// the compartment as the total whatever the query said.
Future<Response> compartmentSearchHandler(
  Request request,
  String compartmentType,
  String compartmentId,
  String resourceType,
  FhirAntDb dbInterface,
) async {
  try {
    // 1. Validate compartment type
    if (!compartmentDefinitions.containsKey(compartmentType)) {
      return outcome(
        404,
        fhir.IssueType.notFound,
        'Unsupported compartment type: $compartmentType',
      );
    }

    // 2. Validate resource type
    final resTypeEnum = fhir.R4ResourceType.fromString(resourceType);
    if (resTypeEnum == null) {
      return outcome(
        400,
        fhir.IssueType.processing,
        'Invalid resource type: $resourceType',
      );
    }

    // 3. Validate resource type is in compartment (the focal type is in its
    // own compartment)
    if (resourceType != compartmentType &&
        !compartmentDefinitions[compartmentType]!.containsKey(resourceType)) {
      return outcome(
        400,
        fhir.IssueType.processing,
        '$resourceType is not part of the $compartmentType compartment',
      );
    }

    // 4. The caller: its patient context, and its scope on the type it is
    // asking for (the middleware checked the compartment type only).
    final outside = _refuseOutsidePatientContext(
      request,
      compartmentType,
      compartmentId,
      resourceType,
      's',
    );
    if (outside != null) return outside;
    final scopes = _scopesOf(request);
    if (scopes != null &&
        !SmartScopeEnforcer.isAuthorized(scopes, resourceType, 's')) {
      return outcome(
        403,
        fhir.IssueType.forbidden,
        'Insufficient scope for s on $resourceType',
      );
    }

    // 5. Verify focal resource exists
    final lookup = await lookupStored(
      request,
      dbInterface,
      compartmentType,
      compartmentId,
    );
    if (lookup is! StoredFound) return lookupRefusal(lookup);

    // 6. The query, parsed as for any search. queryParametersAll keeps every
    // repetition; a repeated parameter is an AND join.
    final queryParams = request.url.queryParametersAll;
    final parsed = SearchParameterParser.parseQueryParameters(queryParams);
    final searchParams = parsed['searchParams'] as Map<String, List<String>>?;
    final hasParams = parsed['has'] as List<HasParameter>?;
    final count = parsed['count'] as int? ?? 20;
    final offset = parsed['offset'] as int? ?? 0;
    final sort = parsed['sort'] as List<String>?;
    final total = parsed['total'] as String?;
    final links = SearchLinks.decide(resourceType, queryParams);
    final scope = CompartmentScope(compartmentType, compartmentId);

    // 7. One scoped search. One row past the page says whether a `next`
    // link is due, so paging does not depend on the count.
    final probeCount = count > 0 ? count + 1 : count;
    final fetched = await dbInterface.search(
      resourceType: resTypeEnum,
      searchParameters: searchParams,
      hasParameters: hasParams,
      count: probeCount,
      offset: offset,
      sort: sort,
      compartment: scope,
    );
    final hasMore = count > 0 && fetched.length > count;
    final results = hasMore ? fetched.sublist(0, count) : fetched;

    int? totalCount;
    if (total != 'none') {
      totalCount = await dbInterface.searchCount(
        resourceType: resTypeEnum,
        searchParameters: searchParams,
        hasParameters: hasParams,
        compartment: scope,
      );
    }

    return _buildSearchsetBundle(
      request,
      results,
      totalCount,
      links: links,
      count: count,
      offset: offset,
      hasMore: hasMore,
    );
  } on ValueSetRefusal catch (e) {
    // `:in` / `:not-in` against a ValueSet the store cannot evaluate or
    // does not hold, as on a type-level search. This was not caught here
    // at all, so it was a 500.
    return outcome(400, issueTypeOfCode(e.issueCode), e.message);
  } on UnsupportedSearchModifier catch (e) {
    // R4 3.1.1.4.4: a SHALL, the same as on a type-level search.
    return outcome(400, fhir.IssueType.notSupported, e.message);
  } on InvalidSearchValue catch (e) {
    // R4B 3.1.1.3: a value that is not valid for its type is an error, not
    // an empty compartment and not a 500.
    return outcome(400, fhir.IssueType.invalid, e.message);
  } on AmbiguousReference catch (e) {
    return outcome(400, fhir.IssueType.invalid, e.message);
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error in compartment search $compartmentType/{id}/$resourceType',
      e,
      stackTrace,
    );
    return outcome(500, fhir.IssueType.processing, 'Internal error');
  }
}

/// Builds a searchset Bundle response with the R4 3.1.1.6 self link and the
/// paging links, all built from the parameters actually used.
Response _buildSearchsetBundle(
  Request request,
  List<fhir.Resource> resources,
  int? total, {
  required SearchLinks links,
  required int count,
  required int offset,
  required bool hasMore,
}) {
  return Response.ok(
    searchsetPage(
      requested: request.requestedUri,
      links: links,
      matches: resources,
      count: count,
      offset: offset,
      hasMore: hasMore,
      total: total,
    ).toJsonString(),
    headers: {'Content-Type': 'application/json'},
  );
}
