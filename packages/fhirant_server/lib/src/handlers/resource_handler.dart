import 'dart:convert';

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
  try {
    FhirantLogging().logInfo(
      'Fetching resources of type: $resourceType',
    );

    final queryParams = request.url.queryParameters;
    
    // Parse query parameters into search params and pagination params
    final parsed = SearchParameterParser.parseQueryParameters(queryParams);
    final searchParams = parsed['searchParams'] as Map<String, List<String>>?;
    final include = parsed['include'] as List<String>?;
    final revinclude = parsed['revinclude'] as List<String>?;

    final count = parsed['count'] as int? ?? 20;
    final offset = parsed['offset'] as int? ?? 0;
    final sort = parsed['sort'] as List<String>?;
    final summary = parsed['summary'] as String?;
    final elements = parsed['elements'] as List<String>?;

    final type = fhir.R4ResourceType.fromString(resourceType);
    if (type == null) {
      FhirantLogging().logWarning(
        'Invalid resource type requested: $resourceType',
      );
      return _validationErrorResponse('Invalid resource type');
    }

    // Handle _summary=count — return bundle with total only, no entries
    if (summary == 'count') {
      int totalCount;
      if (searchParams != null && searchParams.isNotEmpty) {
        totalCount = await dbInterface.searchCount(
          resourceType: type,
          searchParameters: searchParams,
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

    // Use search if search parameters are provided, otherwise use pagination
    final List<fhir.Resource> resources;
    if (searchParams != null && searchParams.isNotEmpty) {
      // Use search functionality
      resources = await dbInterface.search(
        resourceType: type,
        searchParameters: searchParams,
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
    
    // Get total count using searchCount (accurate count query)
    int totalCount;
    if (searchParams != null && searchParams.isNotEmpty) {
      // Use searchCount for accurate count with search parameters
      totalCount = await dbInterface.searchCount(
        resourceType: type,
        searchParameters: searchParams,
      );
    } else {
      // Use getResourceCount for simple count without search
      totalCount = await dbInterface.getResourceCount(type);
    }

    
    // Build pagination links (optional - bundle works without them)
    final links = <fhir.BundleLink>[];
    // Only try to create links if we have valid data
    if (count > 0) {
      try {
      final currentUrl = request.requestedUri;
      
      // First link
      final firstParams = Map<String, String>.from(currentUrl.queryParameters);
      firstParams['_offset'] = '0';
      final firstUrl = currentUrl.replace(queryParameters: firstParams);
      links.add(fhir.BundleLink(
        relation: fhir.FhirString('first'),
        url: fhir.FhirUri(firstUrl.toString()),
      ));
      
      // Previous link (if not on first page)
      if (offset > 0) {
        final prevParams = Map<String, String>.from(currentUrl.queryParameters);
        final prevOffset = (offset - count).clamp(0, double.infinity).toInt();
        prevParams['_offset'] = prevOffset.toString();
        final prevUrl = currentUrl.replace(queryParameters: prevParams);
        links.add(fhir.BundleLink(
          relation: fhir.FhirString('previous'),
          url: fhir.FhirUri(prevUrl.toString()),
        ));
      }
      
      // Next link (if there are more results)
      if (offset + resources.length < totalCount) {
        final nextParams = Map<String, String>.from(currentUrl.queryParameters);
        final nextOffset = offset + count;
        nextParams['_offset'] = nextOffset.toString();
        final nextUrl = currentUrl.replace(queryParameters: nextParams);
        links.add(fhir.BundleLink(
          relation: fhir.FhirString('next'),
          url: fhir.FhirUri(nextUrl.toString()),
        ));
      }
      
      // Last link
      if (count > 0 && totalCount > 0) {
        final lastParams = Map<String, String>.from(currentUrl.queryParameters);
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
      final bundle = fhir.Bundle(
        type: fhir.BundleType.searchset,
        entry: <fhir.BundleEntry>[],
        total: fhir.FhirUnsignedInt(0),
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
      // _include: Include resources referenced by the search results
      for (final includeSpec in include) {
        // Format: ResourceType:searchParam or ResourceType
        final parts = includeSpec.split(':');
        final includeResourceType = parts[0];
        final includeSearchParam = parts.length > 1 ? parts[1] : null;
        
        final includeType = fhir.R4ResourceType.fromString(includeResourceType);
        if (includeType == null) continue;
        
        // Find references in the search results
        for (final resource in resources) {
          try {
            final resourceJson = jsonDecode(resource.toJsonString()) as Map<String, dynamic>;
            final references = _extractReferences(resourceJson, includeSearchParam);
            
            for (final ref in references) {
              if (ref['type'] == includeResourceType && ref['id'] != null) {
                final refId = ref['id'] as String;
                if (!includedResourceIds.contains(refId)) {
                  final refResource = await dbInterface.getResource(includeType, refId);
                  if (refResource != null) {
                    includedResources.add(refResource);
                    includedResourceIds.add(refId);
                  }
                }
              }
            }
          } catch (e) {
            // Skip invalid resources
            continue;
          }
        }
      }
    }
    
    if (revinclude != null && revinclude.isNotEmpty) {
      // _revinclude: Include resources that reference the search results
      for (final revincludeSpec in revinclude) {
        // Format: ResourceType:searchParam or ResourceType
        final parts = revincludeSpec.split(':');
        final revincludeResourceType = parts[0];
        final revincludeSearchParam = parts.length > 1 ? parts[1] : null;
        
        final revincludeType = fhir.R4ResourceType.fromString(revincludeResourceType);
        if (revincludeType == null) continue;
        
        // Search for resources of revincludeType that reference our search results
        final searchResultIds = resources.map((r) => r.id?.toString() ?? '').where((id) => id.isNotEmpty).toSet();
        
        if (searchResultIds.isNotEmpty) {
          // Use reference search to find resources that reference our results
          final revincludeParams = <String, List<String>>{
            revincludeSearchParam ?? 'subject': searchResultIds.toList(),
          };
          
          final revincludeResults = await dbInterface.search(
            resourceType: revincludeType,
            searchParameters: revincludeParams,
          );
          
          for (final revResource in revincludeResults) {
            if (!includedResourceIds.contains(revResource.id?.toString() ?? '')) {
              includedResources.add(revResource);
              includedResourceIds.add(revResource.id?.toString() ?? '');
            }
          }
        }
      }
    }
    
    // Combine search results with included resources
    final allResources = <fhir.Resource>[...resources, ...includedResources];
    
    // Apply response shaping (_summary / _elements) to each resource
    final shapedResources = allResources.map((resource) {
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
    }).toList();

    final bundle = fhir.Bundle(
      type: fhir.BundleType.searchset,
      entry: shapedResources
          .map(
            (resource) {
              final resourceId = resource.id?.toString() ?? '';
              final fullUrl = resourceId.isNotEmpty
                  ? fhir.FhirUri('$baseUrl/$resourceType/$resourceId')
                  : null;
              return fhir.BundleEntry(
                resource: resource,
                fullUrl: fullUrl,
              );
            },
          )
          .toList(),
      total: fhir.FhirUnsignedInt(totalCount),
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

    final result = await dbInterface.saveResource(resource);
    if (result) {
      // Re-fetch to get server-assigned version/lastUpdated
      final type = fhir.R4ResourceType.fromString(resourceType);
      final savedResource = type != null && resource.id != null
          ? await dbInterface.getResource(type, resource.id!.toString())
          : null;
      final responseResource = savedResource ?? resource;

      FhirantLogging().logInfo(
        'Resource of type $resourceType saved successfully with ID: '
        '${resource.id}',
      );

      final headers = FhirHttpHeaders.resourceHeaders(responseResource);
      headers['Location'] = '/$resourceType/${resource.id}';

      return Response(
        201,
        body: responseResource.toJsonString(),
        headers: headers,
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
      return Response(
        200,
        body: responseResource.toJsonString(),
        headers: FhirHttpHeaders.resourceHeaders(responseResource),
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
      // Check If-None-Match for conditional read
      final ifNoneMatch =
          FhirHttpHeaders.parseETag(request.headers['if-none-match']);
      final currentVersion = resource.meta?.versionId?.valueString;
      if (ifNoneMatch != null &&
          currentVersion != null &&
          ifNoneMatch == currentVersion) {
        return Response(304,
            headers: FhirHttpHeaders.resourceHeaders(resource));
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

