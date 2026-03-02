import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:shelf/shelf.dart';
import 'package:fhirant_server/src/utils/search_parser.dart';
import 'package:fhirant_server/src/utils/response_shaper.dart';
import 'package:fhirant_server/src/utils/http_headers.dart';

/// Handler to fetch all resources of a given type
Future<Response> getResourcesHandler(
  Request request,
  String resourceType,
  FhirAntDb dbInterface,
) async {
  final queryParams = request.url.queryParameters;
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
    final bodyParams = Uri.splitQueryString(body);
    // Merge with URL query parameters (URL params take precedence)
    final mergedParams = {...bodyParams, ...request.url.queryParameters};
    return _searchResources(request, resourceType, dbInterface, mergedParams);
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Failed to process POST _search for: $resourceType',
      e,
      stackTrace,
    );
    return _errorResponse('Failed to process search', e.toString());
  }
}

/// Handler for POST system-level search: POST /_search
///
/// Requires `_type` parameter to specify which resource types to search.
/// Aggregates results into a single searchset Bundle.
Future<Response> postSystemSearchHandler(
  Request request,
  FhirAntDb dbInterface,
) async {
  try {
    final body = await request.readAsString();
    // Parse form-encoded body into query parameters
    final bodyParams = Uri.splitQueryString(body);
    // Merge with URL query parameters (URL params take precedence)
    final mergedParams = {...bodyParams, ...request.url.queryParameters};

    // _type is required for system-level search
    final typeParam = mergedParams['_type'];
    if (typeParam == null || typeParam.isEmpty) {
      return _validationErrorResponse(
        'System-level search requires _type parameter',
      );
    }

    final typeNames =
        typeParam.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
    final searchParams =
        Map<String, String>.from(mergedParams)..remove('_type');

    final baseUrl = request.requestedUri.hasPort
        ? '${request.requestedUri.scheme}://${request.requestedUri.host}:${request.requestedUri.port}'
        : '${request.requestedUri.scheme}://${request.requestedUri.host}';

    final allEntries = <fhir.BundleEntry>[];
    int totalCount = 0;

    for (final typeName in typeNames) {
      final type = fhir.R4ResourceType.fromString(typeName);
      if (type == null) {
        return _validationErrorResponse(
          'Invalid resource type in _type: $typeName',
        );
      }

      final parsed =
          SearchParameterParser.parseQueryParameters(searchParams);
      final searchParameters =
          parsed['searchParams'] as Map<String, List<String>>?;
      final hasParams = parsed['has'] as List<HasParameter>?;
      final count = parsed['count'] as int? ?? 20;
      final offset = parsed['offset'] as int? ?? 0;
      final sort = parsed['sort'] as List<String>?;

      final List<fhir.Resource> resources;
      final hasSearchParams =
          searchParameters != null && searchParameters.isNotEmpty;
      final hasHasParams = hasParams != null && hasParams.isNotEmpty;

      if (hasSearchParams || hasHasParams) {
        resources = await dbInterface.search(
          resourceType: type,
          searchParameters: searchParameters,
          hasParameters: hasParams,
          count: count,
          offset: offset,
          sort: sort,
        );
      } else {
        resources = await dbInterface.getResourcesWithPagination(
          resourceType: type,
          count: count,
          offset: offset,
        );
      }

      for (final resource in resources) {
        final resourceId = resource.id?.toString() ?? '';
        final resType = resource.resourceTypeString;
        allEntries.add(fhir.BundleEntry(
          resource: resource,
          fullUrl: resourceId.isNotEmpty
              ? fhir.FhirUri('$baseUrl/$resType/$resourceId')
              : null,
          search: const fhir.BundleSearch(mode: fhir.SearchEntryMode.match),
        ));
      }
      totalCount += resources.length;
    }

    final bundle = fhir.Bundle(
      type: fhir.BundleType.searchset,
      entry: allEntries,
      total: fhir.FhirUnsignedInt(totalCount),
      link: [
        fhir.BundleLink(
          relation: fhir.FhirString('self'),
          url: fhir.FhirUri(request.requestedUri.toString()),
        ),
      ],
    );

    FhirantLogging().logInfo(
      'System search returned $totalCount resources across ${typeNames.length} types',
    );
    return Response.ok(
      bundle.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Failed to process POST /_search',
      e,
      stackTrace,
    );
    return _errorResponse('Failed to process system search', e.toString());
  }
}

/// Shared search logic for both GET and POST _search
Future<Response> _searchResources(
  Request request,
  String resourceType,
  FhirAntDb dbInterface,
  Map<String, String> queryParams,
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

    final type = fhir.R4ResourceType.fromString(resourceType);
    if (type == null) {
      FhirantLogging().logWarning(
        'Invalid resource type requested: $resourceType',
      );
      return _validationErrorResponse('Invalid resource type');
    }

    // Prefer: handling=strict rejects unrecognized _-prefixed parameters
    final handling =
        FhirHttpHeaders.parsePreferHandling(request.headers);
    if (handling == 'strict' &&
        unknownParams != null &&
        unknownParams.isNotEmpty) {
      return _validationErrorResponse(
        'Unrecognized search parameter(s): ${unknownParams.join(', ')}',
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

    // Handle _summary=count — return bundle with total only, no entries
    if (summary == 'count') {
      int totalCount;
      if ((searchParams != null && searchParams.isNotEmpty) || hasHasParams) {
        totalCount = await dbInterface.searchCount(
          resourceType: type,
          searchParameters: searchParams,
          hasParameters: hasParams,
        );
      } else {
        totalCount = await dbInterface.getResourceCount(type);
      }
      final bundle = fhir.Bundle(
        type: fhir.BundleType.searchset,
        total: fhir.FhirUnsignedInt(totalCount),
      );
      return Response.ok(
        bundle.toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Use search if search parameters or _has params are provided
    final List<fhir.Resource> resources;
    if ((searchParams != null && searchParams.isNotEmpty) || hasHasParams) {
      // Use search functionality
      resources = await dbInterface.search(
        resourceType: type,
        searchParameters: searchParams,
        hasParameters: hasParams,
        count: count,
        offset: offset,
        sort: sort,
      );
    } else {
      // Fall back to simple pagination if no search parameters
      resources = await dbInterface.getResourcesWithPagination(
        resourceType: type,
        count: count,
        offset: offset,
      );
    }

    final baseUrl = request.requestedUri.hasPort
        ? '${request.requestedUri.scheme}://${request.requestedUri.host}:${request.requestedUri.port}'
        : '${request.requestedUri.scheme}://${request.requestedUri.host}';

    // Get total count (respects _total parameter)
    // _total=none: skip count entirely, _total=estimate: use same as accurate
    int? totalCount;
    if (total != 'none') {
      if ((searchParams != null && searchParams.isNotEmpty) || hasHasParams) {
        totalCount = await dbInterface.searchCount(
          resourceType: type,
          searchParameters: searchParams,
          hasParameters: hasParams,
        );
      } else {
        totalCount = await dbInterface.getResourceCount(type);
      }
    }

    // Build pagination links (optional - bundle works without them)
    final links = <fhir.BundleLink>[];
    // Only try to create links if we have valid data
    if (count > 0) {
      try {
        final currentUrl = request.requestedUri;

        // Self link (current request URL)
        links.add(fhir.BundleLink(
          relation: fhir.FhirString('self'),
          url: fhir.FhirUri(currentUrl.toString()),
        ));

        // First link
        final firstParams =
            Map<String, String>.from(currentUrl.queryParameters);
        firstParams['_offset'] = '0';
        final firstUrl = currentUrl.replace(queryParameters: firstParams);
        links.add(fhir.BundleLink(
          relation: fhir.FhirString('first'),
          url: fhir.FhirUri(firstUrl.toString()),
        ));

        // Previous link (if not on first page)
        if (offset > 0) {
          final prevParams =
              Map<String, String>.from(currentUrl.queryParameters);
          final prevOffset =
              (offset - count).clamp(0, double.infinity).toInt();
          prevParams['_offset'] = prevOffset.toString();
          final prevUrl = currentUrl.replace(queryParameters: prevParams);
          links.add(fhir.BundleLink(
            relation: fhir.FhirString('previous'),
            url: fhir.FhirUri(prevUrl.toString()),
          ));
        }

        // Next link (if there are more results)
        if (totalCount != null && offset + resources.length < totalCount) {
          final nextParams =
              Map<String, String>.from(currentUrl.queryParameters);
          final nextOffset = offset + count;
          nextParams['_offset'] = nextOffset.toString();
          final nextUrl = currentUrl.replace(queryParameters: nextParams);
          links.add(fhir.BundleLink(
            relation: fhir.FhirString('next'),
            url: fhir.FhirUri(nextUrl.toString()),
          ));
        }

        // Last link
        if (count > 0 && totalCount != null && totalCount > 0) {
          final lastParams =
              Map<String, String>.from(currentUrl.queryParameters);
          final lastOffset = ((totalCount - 1) ~/ count) * count;
          lastParams['_offset'] = lastOffset.toString();
          final lastUrl = currentUrl.replace(queryParameters: lastParams);
          links.add(fhir.BundleLink(
            relation: fhir.FhirString('last'),
            url: fhir.FhirUri(lastUrl.toString()),
          ));
        }
      } catch (e) {
        // If link creation fails, just continue without links
        FhirantLogging().logWarning('Failed to create pagination links: $e');
      }
    }

    // Handle empty results
    if (resources.isEmpty) {
      final selfLink = fhir.BundleLink(
        relation: fhir.FhirString('self'),
        url: fhir.FhirUri(request.requestedUri.toString()),
      );
      final bundle = fhir.Bundle(
        type: fhir.BundleType.searchset,
        entry: <fhir.BundleEntry>[],
        total: totalCount != null ? fhir.FhirUnsignedInt(0) : null,
        link: [selfLink],
      );

      // Use toJson + manual entry to avoid FHIR library serializing empty list as null
      final json = bundle.toJson();
      json['entry'] = <dynamic>[];

      FhirantLogging().logInfo(
        'Successfully fetched 0 resources of type: $resourceType',
      );
      return Response.ok(
        jsonEncode(json),
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

    // _include:iterate — iteratively resolve references from newly included resources
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

    // _revinclude:iterate — iteratively find resources referencing newly included
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
    fhir.Resource _shapeResource(fhir.Resource resource) {
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
      final shaped = _shapeResource(resource);
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
      final shaped = _shapeResource(resource);
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
      link: links.isEmpty ? null : links,
    );

    FhirantLogging().logInfo(
      'Successfully fetched ${resources.length} '
      'resources of type: $resourceType',
    );
    return Response.ok(
      bundle.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Failed to fetch resources of type: $resourceType',
      e,
      stackTrace,
    );
    return _errorResponse('Failed to fetch resources', e.toString());
  }
}

/// Process _include specs: extract references from [sourceResources] and fetch them.
Future<void> _processIncludes(
  List<String> includeSpecs,
  List<fhir.Resource> sourceResources,
  List<fhir.Resource> includedResources,
  Set<String> includedResourceIds,
  FhirAntDb dbInterface, {
  Set<String>? existingIds,
}) async {
  final allIds = existingIds ?? includedResourceIds;

  for (final includeSpec in includeSpecs) {
    final parts = includeSpec.split(':');
    // parts[0] = source type (context)
    final includeSearchParam = parts.length > 1 ? parts[1] : null;
    final targetTypeFilter = parts.length > 2 ? parts[2] : null;
    final isWildcard = includeSearchParam == '*';

    for (final resource in sourceResources) {
      try {
        final resourceJson =
            jsonDecode(resource.toJsonString()) as Map<String, dynamic>;
        final references = _extractReferences(
          resourceJson,
          isWildcard ? null : includeSearchParam,
        );

        for (final ref in references) {
          final refType = ref['type'];
          final refId = ref['id'];
          if (refType == null || refId == null) continue;

          if (targetTypeFilter != null && refType != targetTypeFilter) {
            continue;
          }

          final refTypeEnum = fhir.R4ResourceType.fromString(refType);
          if (refTypeEnum == null) continue;

          final compositeKey = '$refType/$refId';
          if (!allIds.contains(compositeKey) &&
              !includedResourceIds.contains(compositeKey)) {
            final refResource =
                await dbInterface.getResource(refTypeEnum, refId);
            if (refResource != null) {
              includedResources.add(refResource);
              includedResourceIds.add(compositeKey);
            }
          }
        }
      } catch (e) {
        continue;
      }
    }
  }
}

/// Process _revinclude specs: find resources that reference [sourceResources].
Future<void> _processRevIncludes(
  List<String> revincludeSpecs,
  List<fhir.Resource> sourceResources,
  List<fhir.Resource> includedResources,
  Set<String> includedResourceIds,
  FhirAntDb dbInterface, {
  Set<String>? existingIds,
}) async {
  final allIds = existingIds ?? includedResourceIds;

  for (final revincludeSpec in revincludeSpecs) {
    final parts = revincludeSpec.split(':');
    final revincludeResourceType = parts[0];
    // Per FHIR spec, search param is required — skip if missing
    if (parts.length < 2) continue;
    final revincludeSearchParam = parts[1];

    final revincludeType =
        fhir.R4ResourceType.fromString(revincludeResourceType);
    if (revincludeType == null) continue;

    // Build full references (ResourceType/ID) for the search
    final searchResultRefs = sourceResources
        .where((r) => r.id != null && r.id.toString().isNotEmpty)
        .map((r) => '${r.resourceTypeString}/${r.id}')
        .toSet();

    if (searchResultRefs.isNotEmpty) {
      final revincludeParams = <String, List<String>>{
        revincludeSearchParam: searchResultRefs.toList(),
      };

      final revincludeResults = await dbInterface.search(
        resourceType: revincludeType,
        searchParameters: revincludeParams,
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
}

/// Handler to create a resource of a given type
Future<Response> postResourceHandler(
  Request request,
  String resourceType,
  FhirAntDb dbInterface,
) async {
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
          final existing = await dbInterface.search(
            resourceType: type,
            searchParameters: searchParams,
          );

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

    // Ensure resource has an ID before saving so we can re-fetch it
    final resourceWithId = resource.newIdIfNoId();
    final result = await dbInterface.saveResource(resourceWithId);
    if (result) {
      // Re-fetch to get server-assigned version/lastUpdated
      final type = fhir.R4ResourceType.fromString(resourceType);
      final savedResource = type != null
          ? await dbInterface.getResource(type, resourceWithId.id!.toString())
          : null;
      final responseResource = savedResource ?? resourceWithId;

      FhirantLogging().logInfo(
        'Resource of type $resourceType saved successfully with ID: '
        '${resourceWithId.id}',
      );

      final headers = FhirHttpHeaders.resourceHeaders(responseResource);
      headers['Location'] = '/$resourceType/${resourceWithId.id}';

      final preference =
          FhirHttpHeaders.parsePreferReturn(request.headers);
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
      e.toString(),
      statusCode: 400,
    );
  }
}

/// Handler to update a resource by its type and ID
Future<Response> putResourceHandler(
  Request request,
  String resourceType,
  String id,
  FhirAntDb dbInterface,
) async {
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

    // Conditional update: If-Match header
    final ifMatch =
        FhirHttpHeaders.parseETag(request.headers['if-match']);
    if (ifMatch != null) {
      final type = fhir.R4ResourceType.fromString(resourceType);
      if (type == null) {
        return _validationErrorResponse('Invalid resource type');
      }
      final current = await dbInterface.getResource(type, id);
      if (current == null) {
        return Response(
          412,
          body: fhir.OperationOutcome(
            issue: [
              fhir.OperationOutcomeIssue(
                severity: fhir.IssueSeverity.error,
                code: fhir.IssueType.conflict,
                diagnostics:
                    'Resource does not exist (If-Match precondition failed)'
                        .toFhirString,
              ),
            ],
          ).toJsonString(),
          headers: {'Content-Type': 'application/json'},
        );
      }
      final currentVersion = current.meta?.versionId?.valueString;
      if (currentVersion != ifMatch) {
        return Response(
          412,
          body: fhir.OperationOutcome(
            issue: [
              fhir.OperationOutcomeIssue(
                severity: fhir.IssueSeverity.error,
                code: fhir.IssueType.conflict,
                diagnostics:
                    'Version mismatch (If-Match precondition failed)'
                        .toFhirString,
              ),
            ],
          ).toJsonString(),
          headers: {'Content-Type': 'application/json'},
        );
      }
    }

    final success = await dbInterface.saveResource(updatedResource);
    if (success) {
      // Re-fetch to get server-assigned version/lastUpdated
      final type = fhir.R4ResourceType.fromString(resourceType);
      final savedResource = type != null
          ? await dbInterface.getResource(type, id)
          : null;
      final responseResource = savedResource ?? updatedResource;

      FhirantLogging().logInfo(
        'Resource of type $resourceType updated successfully with ID: $id',
      );

      final preference =
          FhirHttpHeaders.parsePreferReturn(request.headers);
      return FhirHttpHeaders.preferredResponse(
        statusCode: 200,
        resource: responseResource,
        headers: FhirHttpHeaders.resourceHeaders(responseResource),
        preference: preference,
      );
    } else {
      FhirantLogging().logError(
        'Failed to update resource of type: $resourceType with ID: $id',
      );
      return _errorResponse(
        'Failed to update resource',
        'Database operation failed',
      );
    }
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error updating resource of type: $resourceType with ID: $id',
      e,
      stackTrace,
    );
    return _errorResponse('Error updating resource', e.toString());
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
      // Check If-None-Match for conditional read (ETag-based)
      final ifNoneMatch =
          FhirHttpHeaders.parseETag(request.headers['if-none-match']);
      final currentVersion = resource.meta?.versionId?.valueString;
      if (ifNoneMatch != null &&
          currentVersion != null &&
          ifNoneMatch == currentVersion) {
        return Response(304,
            headers: FhirHttpHeaders.resourceHeaders(resource));
      }

      // Check If-Modified-Since for conditional read (date-based)
      final ifModifiedSince = request.headers['if-modified-since'];
      if (ifModifiedSince != null) {
        try {
          final sinceDate = HttpDate.parse(ifModifiedSince);
          final lastUpdated = resource.meta?.lastUpdated?.valueDateTime;
          if (lastUpdated != null && !lastUpdated.isAfter(sinceDate)) {
            return Response(304,
                headers: FhirHttpHeaders.resourceHeaders(resource));
          }
        } catch (_) {
          // Ignore malformed If-Modified-Since headers
        }
      }

      FhirantLogging().logInfo(
        'Resource of type $resourceType with ID $id found.',
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
      FhirantLogging().logWarning(
        'Resource of type $resourceType with ID $id not found.',
      );
      return Response(
        404,
        body: jsonEncode({'error': 'Resource not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error fetching resource of type: $resourceType with ID: $id',
      e,
      stackTrace,
    );
    return _errorResponse('Failed to fetch resource', e.toString());
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
        'Resource of type $resourceType with ID $id not found for deletion.',
      );
      return _errorResponse(
        'Resource not found',
        'The resource does not exist',
        statusCode: 404,
      );
    }

    // Conditional delete: If-Match header
    final ifMatch =
        FhirHttpHeaders.parseETag(request.headers['if-match']);
    if (ifMatch != null) {
      final currentVersion = resource.meta?.versionId?.valueString;
      if (currentVersion != ifMatch) {
        return Response(
          412,
          body: fhir.OperationOutcome(
            issue: [
              fhir.OperationOutcomeIssue(
                severity: fhir.IssueSeverity.error,
                code: fhir.IssueType.conflict,
                diagnostics:
                    'Version mismatch (If-Match precondition failed)'
                        .toFhirString,
              ),
            ],
          ).toJsonString(),
          headers: {'Content-Type': 'application/json'},
        );
      }
    }

    final success = await dbInterface.deleteResource(type, id);
    if (success) {
      FhirantLogging().logInfo(
        'Resource of type $resourceType with ID $id deleted successfully.',
      );
      // Return 204 No Content per FHIR spec, or 200 with OperationOutcome
      // Using 204 as it's more RESTful for successful deletion
      return Response(204);
    } else {
      FhirantLogging().logError(
        'Failed to delete resource of type: $resourceType with ID: $id',
      );
      return _errorResponse(
        'Failed to delete resource',
        'Database operation failed',
      );
    }
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error deleting resource of type: $resourceType with ID: $id',
      e,
      stackTrace,
    );
    return _errorResponse('Error deleting resource', e.toString());
  }
}

/// Handler for conditional delete by search (DELETE /<resourceType>?params)
///
/// Per FHIR spec with conditionalDelete: 'single':
/// - 0 matches: return 200 with OperationOutcome (nothing to delete)
/// - 1 match: delete and return 204
/// - Multiple matches: return 412 Precondition Failed
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

    final queryParams = request.url.queryParameters;
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

    if (results.length > 1) {
      return Response(
        412,
        body: fhir.OperationOutcome(
          issue: [
            fhir.OperationOutcomeIssue(
              severity: fhir.IssueSeverity.error,
              code: fhir.IssueType.multipleMatches,
              diagnostics:
                  'Multiple resources (${results.length}) matched the search criteria; '
                          'conditional delete in single mode requires exactly one match'
                      .toFhirString,
            ),
          ],
        ).toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Exactly one match — delete it
    final resource = results.first;
    final id = resource.id?.toString() ?? '';
    final success = await dbInterface.deleteResource(type, id);
    if (success) {
      FhirantLogging().logInfo(
        'Conditional delete: deleted $resourceType/$id',
      );
      return Response(204);
    } else {
      return _errorResponse(
        'Failed to delete resource',
        'Database operation failed',
      );
    }
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error in conditional delete for $resourceType',
      e,
      stackTrace,
    );
    return _errorResponse('Error in conditional delete', e.toString());
  }
}

/// Helper method to extract references from a resource JSON
List<Map<String, String?>> _extractReferences(
  Map<String, dynamic> resourceJson,
  String? searchParam,
) {
  final references = <Map<String, String?>>[];
  
  // If searchParam is specified, look for that specific field
  if (searchParam != null) {
    final value = _getNestedValueFromJson(resourceJson, searchParam);
    if (value is Map && value['reference'] != null) {
      final ref = _parseReference(value['reference'].toString());
      if (ref != null) {
        references.add(ref);
      }
    } else if (value is List) {
      for (final item in value) {
        if (item is Map && item['reference'] != null) {
          final ref = _parseReference(item['reference'].toString());
          if (ref != null) {
            references.add(ref);
          }
        }
      }
    }
  } else {
    // Extract all references from the resource
    _extractAllReferences(resourceJson, references);
  }
  
  return references;
}

Map<String, String?>? _parseReference(String referenceStr) {
  // Parse reference format: ResourceType/id or just id
  if (referenceStr.contains('/')) {
    final parts = referenceStr.split('/');
    if (parts.length >= 2) {
      return {
        'type': parts[parts.length - 2],
        'id': parts[parts.length - 1],
      };
    }
  }
  return null;
}

void _extractAllReferences(Map<String, dynamic> json, List<Map<String, String?>> references) {
  for (final value in json.values) {
    if (value is Map) {
      if (value['reference'] != null) {
        final ref = _parseReference(value['reference'].toString());
        if (ref != null) {
          references.add(ref);
        }
      } else {
        _extractAllReferences(value as Map<String, dynamic>, references);
      }
    } else if (value is List) {
      for (final item in value) {
        if (item is Map) {
          if (item['reference'] != null) {
            final ref = _parseReference(item['reference'].toString());
            if (ref != null) {
              references.add(ref);
            }
          } else {
            _extractAllReferences(item as Map<String, dynamic>, references);
          }
        }
      }
    }
  }
}

dynamic _getNestedValueFromJson(Map<String, dynamic> json, String path) {
  final parts = path.split('.');
  dynamic current = json;
  
  for (final part in parts) {
    if (current is Map<String, dynamic>) {
      current = current[part];
      if (current == null) return null;
    } else if (current is List) {
      if (current.isNotEmpty && current[0] is Map<String, dynamic>) {
        current = (current[0] as Map<String, dynamic>)[part];
      } else {
        return null;
      }
    } else {
      return null;
    }
  }
  
  return current;
}

