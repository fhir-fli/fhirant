import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/services/subscription_service.dart';
import 'package:fhirant_server/src/utils/filter_evaluator.dart';
import 'package:fhirant_server/src/utils/filter_expression.dart';
import 'package:fhirant_server/src/utils/http_headers.dart';
import 'package:fhirant_server/src/utils/patient_scope.dart';
import 'package:fhirant_server/src/utils/response_shaper.dart';
import 'package:fhirant_server/src/utils/search_links.dart';
import 'package:fhirant_server/src/utils/search_parser.dart';
import 'package:shelf/shelf.dart';

/// Handler to fetch all resources of a given type
Future<Response> getResourcesHandler(
  Request request,
  String resourceType,
  FhirAntDb dbInterface,
) async {
  // queryParametersAll, not queryParameters: R4 makes a repeated parameter an
  // AND join, and queryParameters keeps only the LAST value for a repeated
  // key, so every earlier one was silently discarded.
  final queryParams = request.url.queryParametersAll;
  return _searchResources(request, resourceType, dbInterface, queryParams);
}

/// Handler for POST-based search: POST /{resourceType}/_search
Future<Response> postSearchHandler(
  Request request,
  String resourceType,
  FhirAntDb dbInterface,
) async {
  try {
    final body = await request.readAsString();
    // Parse form-encoded body into query parameters
    // A form-encoded body repeats a key the same way a query string does, and
    // splitQueryString collapses those to the last one. Parsed by hand so a
    // repeated parameter in a POST body keeps its AND meaning too.
    final bodyParams = _splitQueryStringAll(body);
    // URL parameters take precedence over the body.
    final mergedParams = {...bodyParams, ...request.url.queryParametersAll};
    return await _searchResources(
      request,
      resourceType,
      dbInterface,
      mergedParams,
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Failed to process POST _search for: $resourceType',
      e,
      stackTrace,
    );
    return _errorResponse('Failed to process search', 'Internal error');
  }
}

/// Handler for POST system-level search: POST /_search
Future<Response> postSystemSearchHandler(
  Request request,
  FhirAntDb dbInterface,
) async {
  final body = await request.readAsString();
  // Every repetition is kept: a repeated parameter is an AND join, so
  // collapsing to one value silently drops half the query.
  final bodyParams = _splitQueryStringAll(body);
  // Merge with URL query parameters (URL params take precedence)
  return systemSearchHandler(
    request,
    dbInterface,
    {...bodyParams, ...request.url.queryParametersAll},
  );
}

/// Handler for GET system-level search: GET [base]?parameter(s)
Future<Response> getSystemSearchHandler(
  Request request,
  FhirAntDb dbInterface,
) =>
    systemSearchHandler(request, dbInterface, request.url.queryParametersAll);

/// The all-types search context.
///
/// R4B search.html 3.1.1.2, read whole 2026-09-06: "All resource types: GET
/// [base]?parameter(s) (parameters common to all types). If the _type
/// parameter is included, all other search parameters SHALL be common to all
/// provided types. If _type is not included, all parameters SHALL be common
/// to all resource types."
///
/// So every search parameter is checked against every type it will run on
/// and refused with a 400 when one type lacks it (this used to run the search
/// anyway, and the store ignored the parameter on the types that lacked it,
/// which returned records the client had filtered out). Without `_type` the
/// types are the ones the store holds, and the parameters must be the ones
/// published on Resource and DomainResource (`_id`, `_lastUpdated`, `_tag`,
/// `_profile`, `_security`, `_source`, `_text`, `_content`, `_list`); it used
/// to be refused outright.
///
/// One result set is paged across the types in name order: each type's count
/// is taken in SQL and the requested page is cut from the concatenation, so
/// `_count` bounds the whole bundle (3.1.1.5.3: "Servers SHALL NOT return
/// more resources than requested") rather than each type. This used to
/// return up to `_count` resources PER type and report the page's size as
/// the total. `_sort` orders within each type.
Future<Response> systemSearchHandler(
  Request request,
  FhirAntDb dbInterface,
  Map<String, List<String>> mergedParams,
) async {
  try {
    // ASSUMPTION, not a spec citation: the AND/OR rule of R4 3.1.1.4.17 cannot
    // apply to _type, because a resource has exactly one type and an AND of
    // two of them matches nothing. So repetitions are unioned here, the same
    // as commas.
    final typeParam = mergedParams['_type'];
    final List<fhir.R4ResourceType> types;
    if (typeParam == null || typeParam.isEmpty) {
      types = await dbInterface.getResourceTypes()
        ..sort((a, b) => a.toString().compareTo(b.toString()));
    } else {
      final names = typeParam
          .expand((value) => value.split(','))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      final resolved = <fhir.R4ResourceType>[];
      for (final name in names) {
        final type = fhir.R4ResourceType.fromString(name);
        if (type == null) {
          return _validationErrorResponse(
            'Invalid resource type in _type: $name',
          );
        }
        resolved.add(type);
      }
      types = resolved;
    }

    final searchParamsIn = Map<String, List<String>>.from(mergedParams)
      ..remove('_type');
    final parsed = SearchParameterParser.parseQueryParameters(searchParamsIn);
    final searchParameters =
        parsed['searchParams'] as Map<String, List<String>>?;
    final hasParams = parsed['has'] as List<HasParameter>?;
    final count = parsed['count'] as int? ?? 20;
    final offset = parsed['offset'] as int? ?? 0;
    final sort = parsed['sort'] as List<String>?;
    final total = parsed['total'] as String?;
    final summary = parsed['summary'] as String?;
    final namedQuery = parsed['query'] as String?;
    final unknownParams = parsed['unknownParams'] as List<String>?;

    // R4 3.1.1.7, the same SHALL as on a type-level search.
    if (namedQuery != null) {
      return _searchRefusal(
        'This server defines no named queries; _query=$namedQuery is not '
        'recognised.',
        fhir.IssueType.notSupported,
      );
    }

    // "all other search parameters SHALL be common to all provided types":
    // each parameter's name must have a definition on every type, or on
    // Resource/DomainResource, which every type inherits.
    final commonScope = typeParam == null || typeParam.isEmpty
        ? const <String>['Resource']
        : types.map((t) => t.toString()).toList();
    for (final key
        in (searchParameters ?? const <String, List<String>>{}).keys) {
      final name = SearchQueryKey.parse(key).name;
      final lacking = commonScope
          .where((t) => searchParameterFor(t, name) == null)
          .toList();
      if (lacking.isNotEmpty) {
        return _searchRefusal(
          typeParam == null || typeParam.isEmpty
              ? 'A search across all resource types takes only the '
                  'parameters common to all types (_id, _lastUpdated, _tag, '
                  '_profile, _security, _source, _text, _content, _list); '
                  '"$name" is not one of them.'
              : 'Parameter "$name" is not defined for ${lacking.join(", ")}; '
                  'with _type, every parameter SHALL be common to all the '
                  'types named.',
          fhir.IssueType.invalid,
        );
      }
    }
    // For the has parameters the target type is named in the parameter
    // itself and validated by the store; for _sort, the rule is the same as
    // for a search parameter.
    for (final rule in sort ?? const <String>[]) {
      final name = rule.startsWith('-') ? rule.substring(1) : rule;
      if (name == '_id' || name == '_lastUpdated') continue;
      final lacking = commonScope
          .where((t) => searchParameterFor(t, name) == null)
          .toList();
      if (lacking.isNotEmpty) {
        return _searchRefusal(
          '_sort=$rule is not defined for ${lacking.join(", ")}.',
          fhir.IssueType.invalid,
        );
      }
    }

    // Prefer: handling=strict, as for a type-level search: an unknown
    // `_`-parameter is refused; anything else unknown was refused above.
    final handling = FhirHttpHeaders.parsePreferHandling(request.headers);
    if (handling == 'strict' &&
        unknownParams != null &&
        unknownParams.isNotEmpty) {
      return _validationErrorResponse(
        'Unsupported search parameter(s): ${unknownParams.join(', ')}',
      );
    }

    // The links: the parameters were checked common, so any one type decides
    // the same used set; `_type` is a control parameter and is kept.
    final links = SearchLinks.decide(commonScope.first, mergedParams);
    final requested = request.requestedUri;

    // Counts per type, in SQL, for the total and to place the page.
    final counts = <fhir.R4ResourceType, int>{};
    for (final type in types) {
      counts[type] = await dbInterface.searchCount(
        resourceType: type,
        searchParameters: searchParameters,
        hasParameters: hasParams,
      );
    }
    final totalCount = counts.values.fold<int>(0, (a, b) => a + b);

    if (summary == 'count' || count == 0) {
      return Response.ok(
        fhir.Bundle(
          type: fhir.BundleType.searchset,
          total: fhir.FhirUnsignedInt(totalCount),
          link: [links.self(requested)],
        ).toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // The page [offset, offset + count) of the concatenation.
    final baseUrl = requested.hasPort
        ? '${requested.scheme}://${requested.host}:${requested.port}'
        : '${requested.scheme}://${requested.host}';
    final allEntries = <fhir.BundleEntry>[];
    var skip = offset;
    var remaining = count > 0 ? count : totalCount;
    for (final type in types) {
      if (remaining <= 0) break;
      final available = counts[type]!;
      if (skip >= available) {
        skip -= available;
        continue;
      }
      final page = await dbInterface.search(
        resourceType: type,
        searchParameters: searchParameters,
        hasParameters: hasParams,
        count: remaining,
        offset: skip,
        sort: sort,
      );
      skip = 0;
      remaining -= page.length;
      for (final resource in page) {
        final resourceId = resource.id?.toString() ?? '';
        final resType = resource.resourceTypeString;
        allEntries.add(
          fhir.BundleEntry(
            resource: resource,
            fullUrl: resourceId.isNotEmpty
                ? fhir.FhirUri('$baseUrl/$resType/$resourceId')
                : null,
            search: const fhir.BundleSearch(mode: fhir.SearchEntryMode.match),
          ),
        );
      }
    }

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
      if (offset + count < totalCount) {
        bundleLinks.add(
          fhir.BundleLink(
            relation: fhir.FhirString('next'),
            url: fhir.FhirUri(
              links.url(requested, offset: offset + count).toString(),
            ),
          ),
        );
      }
      if (totalCount > 0) {
        bundleLinks.add(
          fhir.BundleLink(
            relation: fhir.FhirString('last'),
            url: fhir.FhirUri(
              links
                  .url(requested, offset: ((totalCount - 1) ~/ count) * count)
                  .toString(),
            ),
          ),
        );
      }
    }

    final bundle = fhir.Bundle(
      type: fhir.BundleType.searchset,
      entry: allEntries.isEmpty ? null : allEntries,
      total: total == 'none' ? null : fhir.FhirUnsignedInt(totalCount),
      link: bundleLinks,
    );

    FhirantLogging().logInfo(
      'System search returned ${allEntries.length} of $totalCount resources '
      'across ${types.length} types',
    );
    return Response.ok(
      bundle.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } on UnsupportedSearchModifier catch (e) {
    return _searchRefusal(e.message, fhir.IssueType.notSupported);
  } on InvalidSearchValue catch (e) {
    return _searchRefusal(e.message, fhir.IssueType.invalid);
  } on AmbiguousReference catch (e) {
    return _searchRefusal(e.message, fhir.IssueType.invalid);
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Failed to process system-level search',
      e,
      stackTrace,
    );
    return _errorResponse('Failed to process system search', 'Internal error');
  }
}

/// Shared search logic for both GET and POST _search
Future<Response> _searchResources(
  Request request,
  String resourceType,
  FhirAntDb dbInterface,
  Map<String, List<String>> queryParams,
) async {
  try {
    FhirantLogging().logInfo(
      'Fetching resources of type: $resourceType',
    );

    // Parse query parameters into search params and pagination params
    final parsed = SearchParameterParser.parseQueryParameters(queryParams);
    final searchParams = parsed['searchParams'] as Map<String, List<String>>?;
    final include = parsed['include'] as List<String>?;
    final revinclude = parsed['revinclude'] as List<String>?;
    final includeIterate = parsed['includeIterate'] as List<String>?;
    final revincludeIterate = parsed['revincludeIterate'] as List<String>?;

    final hasParams = parsed['has'] as List<HasParameter>?;
    final count = parsed['count'] as int? ?? 20;
    final offset = parsed['offset'] as int? ?? 0;
    final sort = parsed['sort'] as List<String>?;
    final summary = parsed['summary'] as String?;
    final elements = parsed['elements'] as List<String>?;
    final total = parsed['total'] as String?;
    final unknownParams = parsed['unknownParams'] as List<String>?;
    final filter = parsed['filter'] as String?;
    final contained = parsed['contained'] as String?;
    final containedType = parsed['containedType'] as String?;
    final namedQuery = parsed['query'] as String?;

    final type = fhir.R4ResourceType.fromString(resourceType);
    if (type == null) {
      FhirantLogging().logWarning(
        'Invalid resource type requested: $resourceType',
      );
      return _validationErrorResponse('Invalid resource type');
    }

    // R4 3.1.1.7: "Servers processing search requests SHALL refuse to process
    // a search request if they do not recognize the _query parameter value."
    // This server defines no named queries, so every value is unrecognised.
    if (namedQuery != null) {
      return _searchRefusal(
        'This server defines no named queries; _query=$namedQuery is not '
        'recognised.',
        fhir.IssueType.notSupported,
      );
    }

    // R4 3.1.1.6: the self link carries "the parameters that were actually
    // used", so what was used is decided once, here, and every link is built
    // from it. A parameter the store has no definition for is ignored under
    // lenient handling (3.1.1.3) and refused under strict, whether or not it
    // starts with `_`: the old check only saw `_`-prefixed unknowns, so a
    // strict client sending `?gendr=male` was answered 200 with every
    // patient.
    final links = SearchLinks.decide(resourceType, queryParams);
    final handling = FhirHttpHeaders.parsePreferHandling(request.headers);
    final refused = <String>[...?unknownParams, ...links.ignored];
    if (handling == 'strict' && refused.isNotEmpty) {
      return _validationErrorResponse(
        // "Unsupported" rather than "unrecognized": the spec treats a
        // parameter the server does not know and one it knows but does not
        // implement the same way here, and _filter is the second kind.
        'Unsupported search parameter(s): ${refused.join(', ')}',
      );
    }

    // _contained: "Whether to return resources contained in other resources in
    // the search matches — true | false | both (false is default)".
    //
    // The default is what this server does, so `false` and an absent parameter
    // are answered normally. `true` and `both` are refused rather than
    // silently answered with container matches only: a contained resource is
    // not stored or indexed here, so the search cannot see one, and returning
    // the containers would tell the client its search covered them.
    if (contained != null) {
      const allowed = {'true', 'false', 'both'};
      if (!allowed.contains(contained)) {
        return _validationErrorResponse(
          '_contained must be true, false or both; got "$contained"',
        );
      }
      if (contained != 'false') {
        return _validationErrorResponse(
          '_contained=$contained is not supported: this server does not index '
          "resources held in another resource's contained element, so it "
          'cannot search them. _contained=false, the default, is supported.',
        );
      }
    }
    if (containedType != null) {
      const allowed = {'container', 'contained'};
      if (!allowed.contains(containedType)) {
        return _validationErrorResponse(
          '_containedType must be container or contained; got '
          '"$containedType"',
        );
      }
      // With _contained=false nothing contained is returned, so this cannot
      // change the answer and is not an error on its own.
    }

    // _summary and _elements are mutually exclusive (per FHIR spec)
    if (summary != null &&
        summary != 'false' &&
        elements != null &&
        elements.isNotEmpty) {
      return _validationErrorResponse(
        '_summary and _elements are mutually exclusive; specify only one',
      );
    }

    // Reject _include/_revinclude combined with _summary=text (per FHIR spec)
    final hasIncludes = (include != null && include.isNotEmpty) ||
        (revinclude != null && revinclude.isNotEmpty) ||
        (includeIterate != null && includeIterate.isNotEmpty) ||
        (revincludeIterate != null && revincludeIterate.isNotEmpty);
    if (hasIncludes && summary == 'text') {
      return _validationErrorResponse(
        '_include/_revinclude cannot be combined with _summary=text',
      );
    }

    final hasHasParams = hasParams != null && hasParams.isNotEmpty;

    // Patient-level scope enforcement: the whole search runs inside the
    // patient's compartment, as the compartment context of R4B search.html
    // 3.1.1.2, one SQL condition in the store. A type the compartment does
    // not include comes back empty from the store. This used to fetch every
    // id in the compartment for the type and pass the list back in as `_id`.
    final patientId = extractPatientContext(request);
    final compartment =
        patientId == null ? null : patientCompartment(patientId);

    // _summary=count returns the total and no entries. R4B 3.1.1.5.3: "if
    // _count has the value 0, this shall be treated the same as
    // _summary=count: the server returns a bundle that reports the total
    // number of resources that match in Bundle.total, but with no entries,
    // and no prev/next/last links". The DAO reads a count of 0 as "no page",
    // so without this branch `_count=0` returned every match.
    if (summary == 'count' || count == 0) {
      int totalCount;
      if ((searchParams != null && searchParams.isNotEmpty) ||
          hasHasParams ||
          compartment != null) {
        totalCount = await dbInterface.searchCount(
          resourceType: type,
          searchParameters: searchParams,
          hasParameters: hasParams,
          compartment: compartment,
        );
      } else {
        totalCount = await dbInterface.getResourceCount(type);
      }
      final bundle = fhir.Bundle(
        type: fhir.BundleType.searchset,
        total: fhir.FhirUnsignedInt(totalCount),
        link: [links.self(request.requestedUri)],
      );
      return Response.ok(
        bundle.toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // _filter is evaluated into a set of ids, which then joins the ordinary
    // search parameters as `_id`. Both halves are therefore ANDed, which is
    // what R4 3.1.1.4 says of parameters that appear together, and the filter
    // itself runs through the same index rather than a second engine beside
    // it.
    Set<String>? filterIds;
    if (filter != null && filter.trim().isNotEmpty) {
      try {
        filterIds = await FilterEvaluator(dbInterface, type)
            .evaluate(parseFilter(filter));
      } on FilterParseException catch (e) {
        return _validationErrorResponse('Invalid _filter: $e');
      } on FilterNotSupported catch (e) {
        // R4 3.1.1.4.4 asks for "a clear error message" rather than a result
        // set that means something the client did not ask for.
        return _validationErrorResponse(e.message);
      }
      if (filterIds.isEmpty) {
        return _emptySearchBundle(request, total, links);
      }
    }

    var effectiveSearchParams = searchParams;

    if (filterIds != null) {
      effectiveSearchParams = Map<String, List<String>>.from(
        effectiveSearchParams ?? {},
      );
      final existing = effectiveSearchParams['_id'];
      if (existing == null) {
        // One comma-separated element: the elements of a value list are ANDed
        // since fhir_r4_db 0.11.0, and these ids are alternatives.
        effectiveSearchParams['_id'] = [filterIds.join(',')];
      } else {
        // The client's own `_id` narrows the filter's ids: intersect, which
        // is the AND the two parameters mean together.
        final allowed = existing.expand((value) => value.split(',')).toSet();
        final both = filterIds.intersection(allowed);
        if (both.isEmpty) {
          return _emptySearchBundle(request, total, links);
        }
        effectiveSearchParams['_id'] = [both.join(',')];
      }
    }

    // Use search if search parameters, _has params, or _sort are provided
    final List<fhir.Resource> resources;
    final hasSearchParams =
        effectiveSearchParams != null && effectiveSearchParams.isNotEmpty;
    final hasSort = sort != null && sort.isNotEmpty;
    // One row past the page is fetched and dropped. Its presence is what says
    // a `next` link is due, and it costs one extra row rather than a count:
    // with `_total=none` — the thing that makes a page fast on a large
    // database — the next link used to vanish, because it was derived from
    // `offset + count < total` and there was no total. R4 search.html asks
    // for no total to page; the link is what pages.
    final probeCount = count > 0 ? count + 1 : count;
    final List<fhir.Resource> fetched;
    if (hasSearchParams || hasHasParams || hasSort || compartment != null) {
      // Use search functionality
      fetched = await dbInterface.search(
        resourceType: type,
        searchParameters: effectiveSearchParams,
        hasParameters: hasParams,
        count: probeCount,
        offset: offset,
        sort: sort,
        compartment: compartment,
      );
    } else {
      // Fall back to simple pagination if no search parameters
      fetched = await dbInterface.getResourcesWithPagination(
        resourceType: type,
        count: probeCount,
        offset: offset,
      );
    }
    final hasMore = count > 0 && fetched.length > count;
    resources = hasMore ? fetched.sublist(0, count) : fetched;

    final baseUrl = request.requestedUri.hasPort
        ? '${request.requestedUri.scheme}://${request.requestedUri.host}:${request.requestedUri.port}'
        : '${request.requestedUri.scheme}://${request.requestedUri.host}';

    // Get total count (respects _total parameter)
    // _total=none: skip count entirely, _total=estimate: use same as accurate
    int? totalCount;
    if (total != 'none') {
      if (hasSearchParams || hasHasParams || compartment != null) {
        totalCount = await dbInterface.searchCount(
          resourceType: type,
          searchParameters: effectiveSearchParams,
          hasParameters: hasParams,
          compartment: compartment,
        );
      } else {
        totalCount = await dbInterface.getResourceCount(type);
      }
    }

    // R4 3.1.1.5.3 and 3.1.1.6: every link is built from the parameters
    // actually used, with only `_offset` changed. `first` and `self` are
    // always present; `previous` when there is a page before this one;
    // `next` from the probe row, so it survives `_total=none`; `last` when
    // the total is known.
    final requested = request.requestedUri;
    final bundleLinks = <fhir.BundleLink>[
      links.self(requested),
    ];
    if (count > 0) {
      bundleLinks.add(
        fhir.BundleLink(
          relation: fhir.FhirString('first'),
          url: fhir.FhirUri(links.url(requested, offset: 0).toString()),
        ),
      );
      if (offset > 0) {
        final prevOffset = (offset - count).clamp(0, offset);
        bundleLinks.add(
          fhir.BundleLink(
            relation: fhir.FhirString('previous'),
            url: fhir.FhirUri(
              links.url(requested, offset: prevOffset).toString(),
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
      if (totalCount != null && totalCount > 0) {
        final lastOffset = ((totalCount - 1) ~/ count) * count;
        bundleLinks.add(
          fhir.BundleLink(
            relation: fhir.FhirString('last'),
            url: fhir.FhirUri(
              links.url(requested, offset: lastOffset).toString(),
            ),
          ),
        );
      }
    }

    // Handle empty results
    if (resources.isEmpty) {
      final bundle = fhir.Bundle(
        type: fhir.BundleType.searchset,
        total: totalCount != null ? fhir.FhirUnsignedInt(0) : null,
        link: [links.self(requested)],
      );

      FhirantLogging().logInfo(
        'Successfully fetched 0 resources of type: $resourceType',
      );
      return Response.ok(
        bundle.toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Process _include and _revinclude parameters
    final includedResources = <fhir.Resource>[];
    final includedResourceIds = <String>{};

    if (include != null && include.isNotEmpty) {
      await _processIncludes(
        include,
        resources,
        includedResources,
        includedResourceIds,
        dbInterface,
      );
    }

    // _include:iterate — iteratively resolve references from newly
    // included resources
    if (includeIterate != null && includeIterate.isNotEmpty) {
      var newlyIncluded = List<fhir.Resource>.from(includedResources);
      for (var i = 0; i < 5 && newlyIncluded.isNotEmpty; i++) {
        final nextBatch = <fhir.Resource>[];
        final nextBatchIds = <String>{};
        await _processIncludes(
          includeIterate,
          newlyIncluded,
          nextBatch,
          nextBatchIds,
          dbInterface,
          existingIds: includedResourceIds,
        );
        if (nextBatch.isEmpty) break;
        includedResources.addAll(nextBatch);
        includedResourceIds.addAll(nextBatchIds);
        newlyIncluded = nextBatch;
      }
    }

    if (revinclude != null && revinclude.isNotEmpty) {
      await _processRevIncludes(
        revinclude,
        resources,
        includedResources,
        includedResourceIds,
        dbInterface,
      );
    }

    // _revinclude:iterate — iteratively find resources referencing newly
    // included
    if (revincludeIterate != null && revincludeIterate.isNotEmpty) {
      var newlyIncluded = List<fhir.Resource>.from(includedResources);
      for (var i = 0; i < 5 && newlyIncluded.isNotEmpty; i++) {
        final nextBatch = <fhir.Resource>[];
        final nextBatchIds = <String>{};
        await _processRevIncludes(
          revincludeIterate,
          newlyIncluded,
          nextBatch,
          nextBatchIds,
          dbInterface,
          existingIds: includedResourceIds,
        );
        if (nextBatch.isEmpty) break;
        includedResources.addAll(nextBatch);
        includedResourceIds.addAll(nextBatchIds);
        newlyIncluded = nextBatch;
      }
    }

    // Apply response shaping (_summary / _elements) to each resource
    fhir.Resource shapeResource(fhir.Resource resource) {
      if (summary != null && summary != 'false') {
        final json =
            jsonDecode(resource.toJsonString()) as Map<String, dynamic>;
        final shaped = FhirResponseShaper.shapeSummary(json, summary);
        return fhir.Resource.fromJson(shaped);
      } else if (elements != null && elements.isNotEmpty) {
        final json =
            jsonDecode(resource.toJsonString()) as Map<String, dynamic>;
        final shaped = FhirResponseShaper.shapeElements(json, elements);
        return fhir.Resource.fromJson(shaped);
      }
      return resource;
    }

    // Build match entries (from search results)
    final matchEntries = resources.map((resource) {
      final shaped = shapeResource(resource);
      final resourceId = shaped.id?.toString() ?? '';
      final resType = shaped.resourceTypeString;
      final fullUrl = resourceId.isNotEmpty
          ? fhir.FhirUri('$baseUrl/$resType/$resourceId')
          : null;
      return fhir.BundleEntry(
        resource: shaped,
        fullUrl: fullUrl,
        search: const fhir.BundleSearch(mode: fhir.SearchEntryMode.match),
      );
    }).toList();

    // Build include entries (from _include/_revinclude results)
    final includeEntries = includedResources.map((resource) {
      final shaped = shapeResource(resource);
      final resourceId = shaped.id?.toString() ?? '';
      final resType = shaped.resourceTypeString;
      final fullUrl = resourceId.isNotEmpty
          ? fhir.FhirUri('$baseUrl/$resType/$resourceId')
          : null;
      return fhir.BundleEntry(
        resource: shaped,
        fullUrl: fullUrl,
        search: const fhir.BundleSearch(mode: fhir.SearchEntryMode.include),
      );
    }).toList();

    final bundle = fhir.Bundle(
      type: fhir.BundleType.searchset,
      entry: [...matchEntries, ...includeEntries],
      total: totalCount != null ? fhir.FhirUnsignedInt(totalCount) : null,
      link: bundleLinks,
    );

    FhirantLogging().logInfo(
      'Successfully fetched ${resources.length} '
      'resources of type: $resourceType',
    );
    return Response.ok(
      bundle.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } on UnsupportedSearchModifier catch (e) {
    // R4 3.1.1.4.4 is a SHALL: reject, with a 400 and an OperationOutcome
    // carrying a clear message. Ignoring it would silently change what the
    // query means.
    return _searchRefusal(e.message, fhir.IssueType.notSupported);
  } on InvalidSearchValue catch (e) {
    // R4B 3.1.1.3: "Where the content of the parameter is syntactically
    // incorrect, servers SHOULD return an error." A date that is not a date
    // used to come back as an empty bundle, which told the client there were
    // no such records when the question had not been understood; before
    // that, as a 500.
    return _searchRefusal(e.message, fhir.IssueType.invalid);
  } on AmbiguousReference catch (e) {
    // R4B 3.1.1.4.12: "Servers SHOULD reject a search where the logical id
    // refers to more than one matching resource across different types."
    return _searchRefusal(e.message, fhir.IssueType.invalid);
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Failed to fetch resources of type: $resourceType',
      e,
      stackTrace,
    );
    return _errorResponse('Failed to fetch resources', 'Internal error');
  }
}

/// `_include`: for each `[source type]:[parameter][:target type]`, the
/// resources the matches' reference parameter points at, added with
/// `search.mode=include`.
///
/// R4B search.html 3.1.1.5.4, read whole 2026-09-06: "Both _include and
/// _revinclude are based on search parameters, rather than paths in the
/// resource, since joins, such as chaining, are already done by search
/// parameter." The targets come from the store's reference index by
/// parameter name, so `_include=Observation:patient` follows the `patient`
/// parameter (element `subject`). This used to walk the resource JSON for a
/// key named like the parameter, and found nothing for `patient`,
/// `medication`, or any parameter whose element has another name.
///
/// "Parameter values for both _include and _revinclude have three parts,
/// separated by a : character: The name of the source resource from which the
/// join comes; The name of the search parameter which must be of type
/// reference; (Optional) A specific of type of target resource". A spec whose
/// source type matches none of the sources adds nothing. `*` is "any search
/// parameter of type=reference". "If there is no reference, or no matching
/// resource, the resource cannot be retrieved (e.g. on a different server),
/// then the resource is omitted, and no error is returned."
Future<void> _processIncludes(
  List<String> includeSpecs,
  List<fhir.Resource> sourceResources,
  List<fhir.Resource> includedResources,
  Set<String> includedResourceIds,
  FhirAntDb dbInterface, {
  Set<String>? existingIds,
}) async {
  final allIds = existingIds ?? includedResourceIds;

  // Sources by type: an include spec names the type it joins from.
  final sourceIdsByType = <String, List<String>>{};
  for (final resource in sourceResources) {
    final id = resource.id?.valueString;
    if (id == null || id.isEmpty) continue;
    (sourceIdsByType[resource.resourceTypeString] ??= <String>[]).add(id);
  }

  for (final includeSpec in includeSpecs) {
    final parts = includeSpec.split(':');
    if (parts.length < 2) continue;
    final sourceType = parts[0];
    final parameter = parts[1] == '*' ? null : parts[1];
    final targetTypeFilter = parts.length > 2 ? parts[2] : null;
    final sourceIds = sourceIdsByType[sourceType];
    if (sourceIds == null) continue;

    final targets = await dbInterface.referenceTargets(
      sourceType,
      sourceIds,
      parameter: parameter,
      targetType: targetTypeFilter,
    );
    final sorted = targets.toList()
      ..sort(
        (a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2),
      );
    for (final (refType, refId) in sorted) {
      final refTypeEnum = fhir.R4ResourceType.fromString(refType);
      if (refTypeEnum == null) continue;
      final compositeKey = '$refType/$refId';
      if (allIds.contains(compositeKey) ||
          includedResourceIds.contains(compositeKey)) {
        continue;
      }
      final refResource = await dbInterface.getResource(refTypeEnum, refId);
      if (refResource != null) {
        includedResources.add(refResource);
        includedResourceIds.add(compositeKey);
      }
    }
  }
}

/// `_revinclude`: for each `[type]:[parameter][:target type]`, the resources
/// of that type whose reference parameter points at one of the matches
/// (3.1.1.5.4: "any provenance resources that refer to the prescription").
///
/// One search per spec, with the matches' references as ONE comma-joined
/// value: R4B 3.1.1.4.17 makes a comma an OR and a repeated parameter an AND,
/// and this used to pass one element per match, which since fhir_r4_db
/// 0.11.0 asked for a resource whose parameter pointed at every match at once
/// and returned nothing for any page with more than one match. The optional
/// third part names the target type the parameter must point at, which is
/// the matches' type; a spec naming another type adds nothing.
Future<void> _processRevIncludes(
  List<String> revincludeSpecs,
  List<fhir.Resource> sourceResources,
  List<fhir.Resource> includedResources,
  Set<String> includedResourceIds,
  FhirAntDb dbInterface, {
  Set<String>? existingIds,
}) async {
  final allIds = existingIds ?? includedResourceIds;

  // The matches' references, by their type, so a target-type filter can pick.
  final refsByType = <String, List<String>>{};
  for (final r in sourceResources) {
    final id = r.id?.valueString;
    if (id == null || id.isEmpty) continue;
    (refsByType[r.resourceTypeString] ??= <String>[])
        .add('${r.resourceTypeString}/$id');
  }

  for (final revincludeSpec in revincludeSpecs) {
    final parts = revincludeSpec.split(':');
    // Per FHIR spec, search param is required — skip if missing
    if (parts.length < 2) continue;
    final revincludeType = fhir.R4ResourceType.fromString(parts[0]);
    if (revincludeType == null) continue;
    final revincludeSearchParam = parts[1];
    final targetTypeFilter = parts.length > 2 ? parts[2] : null;

    final refs = targetTypeFilter == null
        ? refsByType.values.expand((v) => v).toList()
        : (refsByType[targetTypeFilter] ?? const <String>[]);
    if (refs.isEmpty) continue;

    final revincludeResults = await dbInterface.search(
      resourceType: revincludeType,
      searchParameters: {
        revincludeSearchParam: [refs.join(',')],
      },
    );

    for (final revResource in revincludeResults) {
      final revType = revResource.resourceTypeString;
      final revId = revResource.id?.toString() ?? '';
      final compositeKey = '$revType/$revId';
      if (!allIds.contains(compositeKey) &&
          !includedResourceIds.contains(compositeKey)) {
        includedResources.add(revResource);
        includedResourceIds.add(compositeKey);
      }
    }
  }
}

/// Handler to create a resource of a given type
Future<Response> postResourceHandler(
  Request request,
  String resourceType,
  FhirAntDb dbInterface, {
  SubscriptionService? subscriptions,
}) async {
  // Defaults to a real service rather than to null. A nullable notifier that
  // quietly does nothing when a caller forgets to pass it is the same defect
  // as an empty exported handler: it looks wired and is not.
  final subs = subscriptions ?? SubscriptionService(dbInterface);
  try {
    final body = await request.readAsString();
    final resource = fhir.Resource.fromJsonString(body);

    if (resource.resourceTypeString != resourceType) {
      FhirantLogging().logWarning(
        'Resource type mismatch: expected $resourceType, '
        'got ${resource.resourceTypeString}',
      );
      return _validationErrorResponse(
        'Resource type in URL does not match resource type in body',
      );
    }

    // Conditional create: If-None-Exist header
    final ifNoneExist = request.headers['if-none-exist'];
    if (ifNoneExist != null && ifNoneExist.isNotEmpty) {
      final type = fhir.R4ResourceType.fromString(resourceType);
      if (type != null) {
        final searchUri = Uri(query: ifNoneExist);
        final searchParams = <String, List<String>>{};
        for (final entry in searchUri.queryParametersAll.entries) {
          searchParams[entry.key] = entry.value;
        }

        if (searchParams.isNotEmpty) {
          final List<fhir.Resource> existing;
          try {
            existing = await dbInterface.search(
              resourceType: type,
              searchParameters: searchParams,
            );
          } on UnsupportedSearchModifier catch (e) {
            return _searchRefusal(
              'If-None-Exist: ${e.message}',
              fhir.IssueType.notSupported,
            );
          } on InvalidSearchValue catch (e) {
            return _searchRefusal(
              'If-None-Exist: ${e.message}',
              fhir.IssueType.invalid,
            );
          } on AmbiguousReference catch (e) {
            return _searchRefusal(
              'If-None-Exist: ${e.message}',
              fhir.IssueType.invalid,
            );
          }

          if (existing.length == 1) {
            return Response.ok(
              existing.first.toJsonString(),
              headers: FhirHttpHeaders.resourceHeaders(existing.first),
            );
          } else if (existing.length > 1) {
            return Response(
              412,
              body: fhir.OperationOutcome(
                issue: [
                  fhir.OperationOutcomeIssue(
                    severity: fhir.IssueSeverity.error,
                    code: fhir.IssueType.duplicate,
                    diagnostics:
                        'Multiple matches found for If-None-Exist criteria'
                            .toFhirString,
                  ),
                ],
              ).toJsonString(),
              headers: {'Content-Type': 'application/json'},
            );
          }
          // No match: proceed with create
        }
      }
    }

    // Patient-level scope enforcement for create
    final createPatientId = extractPatientContext(request);
    if (createPatientId != null) {
      if (!await isNewResourceInPatientCompartment(
        resource,
        createPatientId,
      )) {
        return patientScopeForbiddenResponse(
          resourceType,
          resource.id?.toString() ?? 'new',
          createPatientId,
        );
      }
    }

    // Ensure resource has an ID before saving so we can re-fetch it
    var resourceWithId = resource.newIdIfNoId();
    // R4 subscription.html: a client creates a Subscription as `requested`,
    // and the SERVER decides whether it can process it. Deciding before the
    // save means the stored status is the server's answer, never the client's
    // claim.
    if (resourceWithId is fhir.Subscription) {
      resourceWithId = await subs.activate(resourceWithId);
    }
    final savedResource = await dbInterface.saveResource(resourceWithId);
    if (savedResource != null) {
      final responseResource = savedResource;

      await subs.onResourceChanged(responseResource);

      FhirantLogging().logInfo(
        'Resource of type $resourceType saved successfully with ID: {id}',
      );

      final headers = FhirHttpHeaders.resourceHeaders(responseResource);
      headers['Location'] = '/$resourceType/${resourceWithId.id}';

      final preference = FhirHttpHeaders.parsePreferReturn(request.headers);
      return FhirHttpHeaders.preferredResponse(
        statusCode: 201,
        resource: responseResource,
        headers: headers,
        preference: preference,
      );
    } else {
      FhirantLogging().logError(
        'Failed to save resource of type: $resourceType',
      );
      return _errorResponse(
        'Failed to save resource',
        'Database operation failed',
      );
    }
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error processing request for resource type: $resourceType',
      e,
      stackTrace,
    );
    return _errorResponse(
      'Error processing request',
      'Internal error',
      statusCode: 400,
    );
  }
}

/// Handler to update a resource by its type and ID
Future<Response> putResourceHandler(
  Request request,
  String resourceType,
  String id,
  FhirAntDb dbInterface, {
  SubscriptionService? subscriptions,
}) async {
  final subs = subscriptions ?? SubscriptionService(dbInterface);
  try {
    final body = await request.readAsString();
    final updatedResource = fhir.Resource.fromJsonString(body);

    if (updatedResource.resourceTypeString != resourceType) {
      FhirantLogging().logWarning(
        'Resource type mismatch in update: expected $resourceType, '
        'got ${updatedResource.resourceTypeString}',
      );
      return _validationErrorResponse(
        'Resource type in URL does not match resource type in body',
      );
    }

    // Compare ID as string
    final resourceId = updatedResource.id?.toString() ?? '';
    if (resourceId != id) {
      FhirantLogging().logWarning(
        'Resource ID mismatch in update: expected $id, '
        'got $resourceId',
      );
      return _validationErrorResponse(
        'Resource ID in URL does not match resource ID in body',
      );
    }

    // Patient-level scope enforcement for update
    final updatePatientId = extractPatientContext(request);
    if (updatePatientId != null) {
      if (!await isInPatientCompartment(
        resourceType,
        id,
        updatePatientId,
        dbInterface,
      )) {
        return patientScopeForbiddenResponse(resourceType, id, updatePatientId);
      }
    }

    // Conditional update: If-Match header. The check happens INSIDE the
    // database write (FhirAntDb.saveResource, ifMatchVersion), in the same
    // transaction as the version read, so no other update can land between
    // the check and the write; a mismatch surfaces as VersionConflict.
    final ifMatch = FhirHttpHeaders.parseETag(request.headers['if-match']);

    // Check if this is a create (resource doesn't exist) or update
    final type = fhir.R4ResourceType.fromString(resourceType);
    final isCreate =
        type == null || await dbInterface.getResource(type, id) == null;

    final toSave = updatedResource is fhir.Subscription
        ? await subs.activate(updatedResource)
        : updatedResource;
    final fhir.Resource? savedResource;
    try {
      savedResource = await dbInterface.saveResource(
        toSave,
        ifMatchVersion: ifMatch,
      );
    } on VersionConflict catch (e) {
      return _preconditionFailed(
        e.actual == null
            ? 'Resource does not exist (If-Match precondition failed)'
            : 'Version mismatch (If-Match precondition failed)',
      );
    }
    if (savedResource != null) {
      final responseResource = savedResource;

      await subs.onResourceChanged(responseResource);

      FhirantLogging().logInfo(
        'Resource of type $resourceType '
        '${isCreate ? "created" : "updated"} successfully with ID: {id}',
      );

      final preference = FhirHttpHeaders.parsePreferReturn(request.headers);
      return FhirHttpHeaders.preferredResponse(
        statusCode: isCreate ? 201 : 200,
        resource: responseResource,
        headers: FhirHttpHeaders.resourceHeaders(responseResource),
        preference: preference,
      );
    } else {
      FhirantLogging().logError(
        'Failed to update resource of type: $resourceType with ID: {id}',
      );
      return _errorResponse(
        'Failed to update resource',
        'Database operation failed',
      );
    }
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error updating resource of type: $resourceType with ID: {id}',
      e,
      stackTrace,
    );
    return _errorResponse('Error updating resource', 'Internal error');
  }
}

/// Handler to fetch a specific resource by its type and ID
Future<Response> getResourceByIdHandler(
  Request request,
  String resourceType,
  String id,
  FhirAntDb dbInterface,
) async {
  try {
    final type = fhir.R4ResourceType.fromString(resourceType);
    if (type == null) {
      FhirantLogging().logWarning(
        'Invalid resource type requested: $resourceType',
      );
      return _validationErrorResponse('Invalid resource type');
    }

    final resource = await dbInterface.getResource(type, id);
    if (resource != null) {
      // Patient-level scope enforcement: verify resource is in patient
      // compartment
      final readPatientId = extractPatientContext(request);
      if (readPatientId != null) {
        if (!await isInPatientCompartment(
          resourceType,
          id,
          readPatientId,
          dbInterface,
        )) {
          return patientScopeForbiddenResponse(resourceType, id, readPatientId);
        }
      }

      // Check If-None-Match for conditional read (ETag-based)
      final ifNoneMatch =
          FhirHttpHeaders.parseETag(request.headers['if-none-match']);
      final currentVersion = resource.meta?.versionId?.valueString;
      if (ifNoneMatch != null &&
          currentVersion != null &&
          ifNoneMatch == currentVersion) {
        return Response(
          304,
          headers: FhirHttpHeaders.resourceHeaders(resource),
        );
      }

      // Check If-Modified-Since for conditional read (date-based)
      final ifModifiedSince = request.headers['if-modified-since'];
      if (ifModifiedSince != null) {
        try {
          final sinceDate = HttpDate.parse(ifModifiedSince);
          final lastUpdated = resource.meta?.lastUpdated?.valueDateTime;
          if (lastUpdated != null && !lastUpdated.isAfter(sinceDate)) {
            return Response(
              304,
              headers: FhirHttpHeaders.resourceHeaders(resource),
            );
          }
        } catch (_) {
          // Ignore malformed If-Modified-Since headers
        }
      }

      FhirantLogging().logInfo(
        'Resource of type $resourceType with ID: {id} found.',
      );

      // Apply response shaping
      final queryParams = request.url.queryParameters;
      final summary = queryParams['_summary'];
      final elementsParam = queryParams['_elements'];
      final elements = elementsParam
          ?.split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      // _summary and _elements are mutually exclusive (per FHIR spec)
      if (summary != null &&
          summary != 'false' &&
          elements != null &&
          elements.isNotEmpty) {
        return _validationErrorResponse(
          '_summary and _elements are mutually exclusive; specify only one',
        );
      }

      String responseBody;
      if (summary != null && summary != 'false') {
        final json =
            jsonDecode(resource.toJsonString()) as Map<String, dynamic>;
        final shaped = FhirResponseShaper.shapeSummary(json, summary);
        responseBody = jsonEncode(shaped);
      } else if (elements != null && elements.isNotEmpty) {
        final json =
            jsonDecode(resource.toJsonString()) as Map<String, dynamic>;
        final shaped = FhirResponseShaper.shapeElements(json, elements);
        responseBody = jsonEncode(shaped);
      } else {
        responseBody = resource.toJsonString();
      }

      return Response.ok(
        responseBody,
        headers: FhirHttpHeaders.resourceHeaders(resource),
      );
    } else {
      // Check if resource was previously deleted (has history but no current)
      final history = await dbInterface.getResourceHistory(type, id);
      if (history.isNotEmpty) {
        FhirantLogging().logWarning(
          'Resource $resourceType/$id was deleted (410 Gone).',
        );
        return Response(
          410,
          body: fhir.OperationOutcome(
            issue: [
              fhir.OperationOutcomeIssue(
                severity: fhir.IssueSeverity.error,
                code: fhir.IssueType.deleted,
                diagnostics:
                    'Resource $resourceType/$id has been deleted'.toFhirString,
              ),
            ],
          ).toJsonString(),
          headers: {'Content-Type': 'application/json'},
        );
      }

      FhirantLogging().logWarning(
        'Resource of type $resourceType with ID: {id} not found.',
      );
      return Response(
        404,
        body: jsonEncode({'error': 'Resource not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error fetching resource of type: $resourceType with ID: {id}',
      e,
      stackTrace,
    );
    return _errorResponse('Failed to fetch resource', 'Internal error');
  }
}

/// Utility for creating a generic error response
Response _errorResponse(
  String message,
  String details, {
  int statusCode = 500,
}) {
  final operationOutcome = fhir.OperationOutcome(
    issue: [
      fhir.OperationOutcomeIssue(
        severity: fhir.IssueSeverity.error,
        code: fhir.IssueType.exception,
        diagnostics: '$message: $details'.toFhirString,
      ),
    ],
  );

  FhirantLogging().logWarning('Error Response: $message - $details');
  return Response(
    statusCode,
    body: operationOutcome.toJsonString(),
    headers: {'Content-Type': 'application/json'},
  );
}

/// Utility for creating a validation error response
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

  FhirantLogging().logWarning('Validation Error: $message');
  return Response(
    400,
    body: operationOutcome.toJsonString(),
    headers: {'Content-Type': 'application/json'},
  );
}

/// Handler to delete a resource by its type and ID
Future<Response> deleteResourceHandler(
  Request request,
  String resourceType,
  String id,
  FhirAntDb dbInterface,
) async {
  try {
    final type = fhir.R4ResourceType.fromString(resourceType);
    if (type == null) {
      FhirantLogging().logWarning(
        'Invalid resource type requested: $resourceType',
      );
      return _validationErrorResponse('Invalid resource type');
    }

    // Check if resource exists before attempting to delete
    final resource = await dbInterface.getResource(type, id);
    if (resource == null) {
      FhirantLogging().logWarning(
        'Resource of type $resourceType with ID: {id} not found for deletion.',
      );
      return _errorResponse(
        'Resource not found',
        'The resource does not exist',
        statusCode: 404,
      );
    }

    // Patient-level scope enforcement for delete
    final deletePatientId = extractPatientContext(request);
    if (deletePatientId != null) {
      if (!await isInPatientCompartment(
        resourceType,
        id,
        deletePatientId,
        dbInterface,
      )) {
        return patientScopeForbiddenResponse(resourceType, id, deletePatientId);
      }
    }

    // Conditional delete: If-Match header, checked inside the delete's
    // transaction (FhirAntDb.deleteResource, ifMatchVersion).
    final ifMatch = FhirHttpHeaders.parseETag(request.headers['if-match']);
    final bool success;
    try {
      success = await dbInterface.deleteResource(
        type,
        id,
        ifMatchVersion: ifMatch,
      );
    } on VersionConflict {
      return _preconditionFailed(
        'Version mismatch (If-Match precondition failed)',
      );
    }
    if (success) {
      FhirantLogging().logInfo(
        'Resource of type $resourceType with ID: {id} deleted successfully.',
      );
      // Return 204 No Content per FHIR spec, or 200 with OperationOutcome
      // Using 204 as it's more RESTful for successful deletion
      return Response(204);
    } else {
      FhirantLogging().logError(
        'Failed to delete resource of type: $resourceType with ID: {id}',
      );
      return _errorResponse(
        'Failed to delete resource',
        'Database operation failed',
      );
    }
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error deleting resource of type: $resourceType with ID: {id}',
      e,
      stackTrace,
    );
    return _errorResponse('Error deleting resource', 'Internal error');
  }
}

/// Handler for conditional delete by search (DELETE /`<resourceType>`?params)
///
/// Supports both single and multiple deletion:
/// - 0 matches: return 200 with OperationOutcome (nothing to delete)
/// - 1+ matches: delete all and return 204
Future<Response> conditionalDeleteHandler(
  Request request,
  String resourceType,
  FhirAntDb dbInterface,
) async {
  try {
    final type = fhir.R4ResourceType.fromString(resourceType);
    if (type == null) {
      FhirantLogging().logWarning(
        'Invalid resource type for conditional delete: $resourceType',
      );
      return _validationErrorResponse('Invalid resource type');
    }

    final queryParams = request.url.queryParametersAll;
    final parsed = SearchParameterParser.parseQueryParameters(queryParams);
    final searchParams = parsed['searchParams'] as Map<String, List<String>>?;

    if (searchParams == null || searchParams.isEmpty) {
      return _validationErrorResponse(
        'Conditional delete requires at least one search parameter',
      );
    }

    final results = await dbInterface.search(
      resourceType: type,
      searchParameters: searchParams,
    );

    if (results.isEmpty) {
      return Response.ok(
        fhir.OperationOutcome(
          issue: [
            fhir.OperationOutcomeIssue(
              severity: fhir.IssueSeverity.information,
              code: fhir.IssueType.notFound,
              diagnostics:
                  'No resources matched the search criteria'.toFhirString,
            ),
          ],
        ).toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Delete all matching resources
    var deleted = 0;
    for (final resource in results) {
      final id = resource.id?.toString() ?? '';
      if (await dbInterface.deleteResource(type, id)) {
        deleted++;
      }
    }

    FhirantLogging().logInfo(
      'Conditional delete: deleted $deleted of ${results.length} '
      '$resourceType resources',
    );
    return Response(204);
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error in conditional delete for $resourceType',
      e,
      stackTrace,
    );
    return _errorResponse('Error in conditional delete', 'Internal error');
  }
}

/// Helper method to extract references from a resource JSON
/// Returns an empty searchset Bundle response.
Response _emptySearchBundle(
  Request request,
  String? total,
  SearchLinks links,
) {
  final bundle = fhir.Bundle(
    type: fhir.BundleType.searchset,
    total: total != 'none' ? fhir.FhirUnsignedInt(0) : null,
    link: [links.self(request.requestedUri)],
  );
  return Response.ok(
    bundle.toJsonString(),
    headers: {'Content-Type': 'application/json'},
  );
}

/// A 400 with an OperationOutcome for a search the store refused.
///
/// Three refusals come out of fhir_r4_db and each names its rule: an
/// unsupported modifier (R4 3.1.1.4.4, a SHALL: "using an HTTP 400 error with
/// an OperationOutcome with a clear error message"; issue code
/// `not-supported`), a value that is not syntactically valid for its
/// parameter's type (3.1.1.3; `invalid`), and a bare logical id that refers
/// to more than one resource type (3.1.1.4.12; `invalid`). The store's
/// message already says what was asked for and what was allowed.
Response _searchRefusal(String message, fhir.IssueType code) {
  FhirantLogging().logInfo('Rejected search: $message');
  return Response(
    400,
    body: fhir.OperationOutcome(
      issue: [
        fhir.OperationOutcomeIssue(
          severity: fhir.IssueSeverity.error,
          code: code,
          diagnostics: message.toFhirString,
        ),
      ],
    ).toJsonString(),
    headers: {'Content-Type': 'application/json'},
  );
}

/// Splits a form-encoded body keeping EVERY value for a repeated key.
///
/// `Uri.splitQueryString` returns `Map<String, String>` and keeps only the
/// last, which loses the AND join R4 3.1.1.4.17 gives a repeated parameter.
Map<String, List<String>> _splitQueryStringAll(String body) {
  final result = <String, List<String>>{};
  for (final pair in body.split('&')) {
    if (pair.isEmpty) {
      continue;
    }
    final equals = pair.indexOf('=');
    final key = equals < 0 ? pair : pair.substring(0, equals);
    final value = equals < 0 ? '' : pair.substring(equals + 1);
    (result[Uri.decodeQueryComponent(key)] ??= <String>[])
        .add(Uri.decodeQueryComponent(value));
  }
  return result;
}

/// 412 with an OperationOutcome, for an `If-Match` the store did not accept.
Response _preconditionFailed(String diagnostics) => Response(
      412,
      body: fhir.OperationOutcome(
        issue: [
          fhir.OperationOutcomeIssue(
            severity: fhir.IssueSeverity.error,
            code: fhir.IssueType.conflict,
            diagnostics: diagnostics.toFhirString,
          ),
        ],
      ).toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
