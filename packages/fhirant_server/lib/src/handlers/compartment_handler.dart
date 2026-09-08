import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/utils/patient_scope.dart';
import 'package:fhirant_server/src/utils/search_links.dart';
import 'package:fhirant_server/src/utils/search_parser.dart';
import 'package:fhirant_server/src/utils/smart_scopes.dart';
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
) {
  final patientId = extractPatientContext(request);
  if (patientId == null) return null;
  if (compartmentType == 'Patient' && compartmentId == patientId) return null;
  return patientScopeForbiddenResponse(
    compartmentType,
    compartmentId,
    patientId,
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
      return _operationOutcome(
        400,
        'Unsupported compartment type: $compartmentType. '
        'Supported types: ${supportedCompartments.join(', ')}',
      );
    }

    // 2. Fetch focal resource
    final focalType = fhir.R4ResourceType.fromString(compartmentType);
    if (focalType == null) {
      return _operationOutcome(400, 'Invalid resource type: $compartmentType');
    }
    final outside = _refuseOutsidePatientContext(request, compartmentType, id);
    if (outside != null) return outside;
    final focalResource = await dbInterface.getResource(focalType, id);
    if (focalResource == null) {
      return _operationOutcome(
        404,
        '$compartmentType/$id not found',
      );
    }

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
    }
    final pageError = pageArgumentError(countParam, offsetParam);
    if (pageError != null) {
      return _operationOutcome(400, pageError, fhir.IssueType.invalid);
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
        return _operationOutcome(
          403,
          'Insufficient scope to read ${unreadable.join(', ')}; narrow the '
          'request with _type or obtain a scope covering them.',
          fhir.IssueType.forbidden,
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
    for (final (resTypeEnum, resId) in pageIds) {
      final resource = await dbInterface.getResource(resTypeEnum, resId);
      if (resource != null) paged.add(resource);
    }

    // 6. Links. The self link repeats the request with its page position;
    // next and previous move `_offset` by the page size and keep every
    // other parameter, `_count` included, as the client sent it.
    final requested = request.requestedUri;
    Uri pageUrl(int pageOffset) => requested.replace(
          queryParameters: {
            ...requested.queryParametersAll,
            '_offset': ['$pageOffset'],
          },
        );
    final links = <fhir.BundleLink>[
      fhir.BundleLink(
        relation: fhir.FhirString('self'),
        url: fhir.FhirUri(pageUrl(offset).toString()),
      ),
      if (count > 0 && offset > 0)
        fhir.BundleLink(
          relation: fhir.FhirString('previous'),
          url: fhir.FhirUri(
            pageUrl((offset - count).clamp(0, offset)).toString(),
          ),
        ),
      if (count > 0 && offset + count < total)
        fhir.BundleLink(
          relation: fhir.FhirString('next'),
          url: fhir.FhirUri(pageUrl(offset + count).toString()),
        ),
    ];

    // 7. Build Bundle
    final baseUrl = _baseUrl(request);

    if (paged.isEmpty) {
      final bundle = fhir.Bundle(
        type: fhir.BundleType.searchset,
        total: fhir.FhirUnsignedInt(total),
        link: links,
      );
      return Response.ok(
        bundle.toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final entries = paged.map((resource) {
      final resType = resource.resourceTypeString;
      final resId = resource.id?.toString() ?? '';
      return fhir.BundleEntry(
        resource: resource,
        fullUrl:
            resId.isNotEmpty ? fhir.FhirUri('$baseUrl/$resType/$resId') : null,
      );
    }).toList();

    final bundle = fhir.Bundle(
      type: fhir.BundleType.searchset,
      total: fhir.FhirUnsignedInt(total),
      entry: entries,
      link: links,
    );

    FhirantLogging().logInfo(
      '\$everything for $compartmentType/$id: $total resources, '
      '${entries.length} on this page',
    );

    return Response.ok(
      bundle.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error in \$everything for $compartmentType/$id',
      e,
      stackTrace,
    );
    return _operationOutcome(500, 'Internal error');
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
      return _operationOutcome(
        404,
        'Unsupported compartment type: $compartmentType',
      );
    }

    // 2. Validate resource type
    final resTypeEnum = fhir.R4ResourceType.fromString(resourceType);
    if (resTypeEnum == null) {
      return _operationOutcome(400, 'Invalid resource type: $resourceType');
    }

    // 3. Validate resource type is in compartment (the focal type is in its
    // own compartment)
    if (resourceType != compartmentType &&
        !compartmentDefinitions[compartmentType]!.containsKey(resourceType)) {
      return _operationOutcome(
        400,
        '$resourceType is not part of the $compartmentType compartment',
      );
    }

    // 4. The caller: its patient context, and its scope on the type it is
    // asking for (the middleware checked the compartment type only).
    final outside = _refuseOutsidePatientContext(
      request,
      compartmentType,
      compartmentId,
    );
    if (outside != null) return outside;
    final scopes = _scopesOf(request);
    if (scopes != null &&
        !SmartScopeEnforcer.isAuthorized(scopes, resourceType, 's')) {
      return _operationOutcome(
        403,
        'Insufficient scope for s on $resourceType',
        fhir.IssueType.forbidden,
      );
    }

    // 5. Verify focal resource exists
    final focalType = fhir.R4ResourceType.fromString(compartmentType);
    if (focalType == null) {
      return _operationOutcome(
        400,
        'Invalid compartment type: $compartmentType',
      );
    }
    final focalResource =
        await dbInterface.getResource(focalType, compartmentId);
    if (focalResource == null) {
      return _operationOutcome(
        404,
        '$compartmentType/$compartmentId not found',
      );
    }

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
  } on UnsupportedSearchModifier catch (e) {
    // R4 3.1.1.4.4: a SHALL, the same as on a type-level search.
    return _operationOutcome(400, e.message, fhir.IssueType.notSupported);
  } on InvalidSearchValue catch (e) {
    // R4B 3.1.1.3: a value that is not valid for its type is an error, not
    // an empty compartment and not a 500.
    return _operationOutcome(400, e.message, fhir.IssueType.invalid);
  } on AmbiguousReference catch (e) {
    return _operationOutcome(400, e.message, fhir.IssueType.invalid);
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error in compartment search $compartmentType/$compartmentId/$resourceType',
      e,
      stackTrace,
    );
    return _operationOutcome(500, 'Internal error');
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
  final requested = request.requestedUri;
  final bundleLinks = <fhir.BundleLink>[links.self(requested)];
  if (count > 0) {
    bundleLinks.add(
      fhir.BundleLink(
        relation: fhir.FhirString('first'),
        url: fhir.FhirUri(links.url(requested, offset: 0).toString()),
      ),
    );
    if (offset > 0) {
      bundleLinks.add(
        fhir.BundleLink(
          relation: fhir.FhirString('previous'),
          url: fhir.FhirUri(
            links
                .url(requested, offset: (offset - count).clamp(0, offset))
                .toString(),
          ),
        ),
      );
    }
    if (hasMore) {
      bundleLinks.add(
        fhir.BundleLink(
          relation: fhir.FhirString('next'),
          url: fhir.FhirUri(
            links.url(requested, offset: offset + count).toString(),
          ),
        ),
      );
    }
    if (total != null && total > 0) {
      bundleLinks.add(
        fhir.BundleLink(
          relation: fhir.FhirString('last'),
          url: fhir.FhirUri(
            links
                .url(requested, offset: ((total - 1) ~/ count) * count)
                .toString(),
          ),
        ),
      );
    }
  }

  final baseUrl = _baseUrl(request);
  final entries = resources.map((resource) {
    final resType = resource.resourceTypeString;
    final resId = resource.id?.toString() ?? '';
    return fhir.BundleEntry(
      resource: resource,
      fullUrl:
          resId.isNotEmpty ? fhir.FhirUri('$baseUrl/$resType/$resId') : null,
      search: const fhir.BundleSearch(mode: fhir.SearchEntryMode.match),
    );
  }).toList();

  final bundle = fhir.Bundle(
    type: fhir.BundleType.searchset,
    total: total != null ? fhir.FhirUnsignedInt(total) : null,
    entry: entries.isEmpty ? null : entries,
    link: bundleLinks,
  );

  return Response.ok(
    bundle.toJsonString(),
    headers: {'Content-Type': 'application/json'},
  );
}

/// Extracts the base URL from a request.
String _baseUrl(Request request) {
  final uri = request.requestedUri;
  return uri.hasPort
      ? '${uri.scheme}://${uri.host}:${uri.port}'
      : '${uri.scheme}://${uri.host}';
}

/// Returns an OperationOutcome response.
Response _operationOutcome(
  int statusCode,
  String message, [
  fhir.IssueType? code,
]) {
  final outcome = fhir.OperationOutcome(
    issue: [
      fhir.OperationOutcomeIssue(
        severity: statusCode >= 500
            ? fhir.IssueSeverity.fatal
            : fhir.IssueSeverity.error,
        code: code ??
            (statusCode == 404
                ? fhir.IssueType.notFound
                : fhir.IssueType.processing),
        diagnostics: message.toFhirString,
      ),
    ],
  );
  return Response(
    statusCode,
    body: outcome.toJsonString(),
    headers: {'Content-Type': 'application/json'},
  );
}
