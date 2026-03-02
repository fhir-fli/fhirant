import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:shelf/shelf.dart';

/// Handler for CodeSystem/$validate-code and ValueSet/$validate-code.
///
/// Supports both GET (query params) and POST (Parameters resource body).
/// Parameters: system, code, display, url (for ValueSet), coding, valueSet.
Future<Response> validateCodeHandler(
  Request request,
  FhirAntDb dbInterface, [
  String? resourceType,
  String? id,
]) async {
  try {
    final params = await _extractOperationParams(request);

    final code = params['code'];
    final system = params['system'];
    final display = params['display'];
    final url = params['url'];
    final coding = params['coding'] as Map<String, dynamic>?;

    // Extract code/system from coding if provided
    final effectiveCode = code ?? (coding?['code'] as String?);
    final effectiveSystem = system ?? (coding?['system'] as String?);

    if (effectiveCode == null) {
      return _errorResponse(400, 'Parameter "code" or "coding" is required');
    }

    // Instance-level: validate against specific resource
    if (id != null && resourceType != null) {
      final type = fhir.R4ResourceType.fromString(resourceType);
      if (type == null) {
        return _errorResponse(400, 'Invalid resource type: $resourceType');
      }
      final resource = await dbInterface.getResource(type, id);
      if (resource == null) {
        return _errorResponse(404, '$resourceType/$id not found');
      }

      if (resourceType == 'CodeSystem' && resource is fhir.CodeSystem) {
        return _validateAgainstCodeSystem(
            resource, effectiveCode, effectiveSystem, display);
      } else if (resourceType == 'ValueSet' && resource is fhir.ValueSet) {
        return _validateAgainstValueSet(
            resource, effectiveCode, effectiveSystem, display, dbInterface);
      }
      return _errorResponse(
          400, '\$validate-code only supported for CodeSystem and ValueSet');
    }

    // Type-level or system-level: look up by URL/system
    if (resourceType == 'CodeSystem' || (resourceType == null && url == null)) {
      if (effectiveSystem == null && url == null) {
        return _errorResponse(
            400, 'Parameter "system" or "url" is required for CodeSystem');
      }
      final lookupUrl = url ?? effectiveSystem;
      final codeSystem = await _findCodeSystemByUrl(lookupUrl!, dbInterface);
      if (codeSystem == null) {
        return _validationResult(
          result: false,
          message: 'CodeSystem not found: $lookupUrl',
        );
      }
      return _validateAgainstCodeSystem(
          codeSystem, effectiveCode, effectiveSystem, display);
    }

    if (resourceType == 'ValueSet') {
      if (url == null) {
        return _errorResponse(
            400, 'Parameter "url" is required for ValueSet');
      }
      final valueSet = await _findValueSetByUrl(url, dbInterface);
      if (valueSet == null) {
        return _validationResult(
          result: false,
          message: 'ValueSet not found: $url',
        );
      }
      return _validateAgainstValueSet(
          valueSet, effectiveCode, effectiveSystem, display, dbInterface);
    }

    return _errorResponse(400, 'Unable to determine target for validation');
  } catch (e, stackTrace) {
    FhirantLogging().logError(
        'Terminology \$validate-code failed', e, stackTrace);
    return _errorResponse(500, 'Internal error: $e');
  }
}

/// Handler for CodeSystem/$lookup.
///
/// Returns properties of a code from a CodeSystem.
/// Parameters: system, code, version, property, coding.
Future<Response> lookupHandler(
  Request request,
  FhirAntDb dbInterface, [
  String? id,
]) async {
  try {
    final params = await _extractOperationParams(request);

    final code = params['code'];
    final system = params['system'];
    final coding = params['coding'] as Map<String, dynamic>?;

    final effectiveCode = code ?? (coding?['code'] as String?);
    final effectiveSystem = system ?? (coding?['system'] as String?);

    if (effectiveCode == null) {
      return _errorResponse(400, 'Parameter "code" or "coding" is required');
    }

    // Instance-level: lookup in specific CodeSystem
    fhir.CodeSystem? codeSystem;
    if (id != null) {
      final resource =
          await dbInterface.getResource(fhir.R4ResourceType.CodeSystem, id);
      if (resource == null) {
        return _errorResponse(404, 'CodeSystem/$id not found');
      }
      codeSystem = resource as fhir.CodeSystem;
    } else {
      // Type-level: find by system URL
      if (effectiveSystem == null) {
        return _errorResponse(
            400, 'Parameter "system" or "coding.system" is required');
      }
      codeSystem = await _findCodeSystemByUrl(effectiveSystem, dbInterface);
      if (codeSystem == null) {
        return _errorResponse(404, 'CodeSystem not found: $effectiveSystem');
      }
    }

    // Find the concept in the code system
    final concept = _findConcept(codeSystem.concept, effectiveCode);
    if (concept == null) {
      return _errorResponse(
        404,
        'Code "$effectiveCode" not found in CodeSystem '
        '${codeSystem.url?.valueString ?? codeSystem.id?.toString() ?? 'unknown'}',
      );
    }

    // Build response Parameters
    final responseParams = <fhir.ParametersParameter>[
      fhir.ParametersParameter(
        name: fhir.FhirString('name'),
        valueString: fhir.FhirString(
            codeSystem.name?.valueString ?? codeSystem.title?.valueString ?? ''),
      ),
      fhir.ParametersParameter(
        name: fhir.FhirString('display'),
        valueString: fhir.FhirString(concept.display?.valueString ?? ''),
      ),
    ];

    if (codeSystem.version?.valueString != null) {
      responseParams.add(fhir.ParametersParameter(
        name: fhir.FhirString('version'),
        valueString: codeSystem.version!,
      ));
    }

    if (concept.definition?.valueString != null) {
      responseParams.add(fhir.ParametersParameter(
        name: fhir.FhirString('definition'),
        valueString: concept.definition!,
      ));
    }

    // Add designations
    if (concept.designation != null) {
      for (final d in concept.designation!) {
        responseParams.add(fhir.ParametersParameter(
          name: fhir.FhirString('designation'),
          part_: [
            if (d.language != null)
              fhir.ParametersParameter(
                name: fhir.FhirString('language'),
                valueCode: d.language!,
              ),
            if (d.use != null)
              fhir.ParametersParameter(
                name: fhir.FhirString('use'),
                valueCoding: d.use!,
              ),
            fhir.ParametersParameter(
              name: fhir.FhirString('value'),
              valueString: d.value,
            ),
          ],
        ));
      }
    }

    // Add code properties
    if (concept.property != null) {
      for (final p in concept.property!) {
        final propParts = <fhir.ParametersParameter>[
          fhir.ParametersParameter(
            name: fhir.FhirString('code'),
            valueCode: p.code,
          ),
        ];
        // Add the property value based on its type
        final propJson = p.toJson();
        if (propJson.containsKey('valueCode')) {
          propParts.add(fhir.ParametersParameter(
            name: fhir.FhirString('value'),
            valueCode: fhir.FhirCode(propJson['valueCode'] as String),
          ));
        } else if (propJson.containsKey('valueString')) {
          propParts.add(fhir.ParametersParameter(
            name: fhir.FhirString('value'),
            valueString: fhir.FhirString(propJson['valueString'] as String),
          ));
        } else if (propJson.containsKey('valueBoolean')) {
          propParts.add(fhir.ParametersParameter(
            name: fhir.FhirString('value'),
            valueBoolean: fhir.FhirBoolean(propJson['valueBoolean'] as bool),
          ));
        } else if (propJson.containsKey('valueInteger')) {
          propParts.add(fhir.ParametersParameter(
            name: fhir.FhirString('value'),
            valueInteger: fhir.FhirInteger(propJson['valueInteger'] as int),
          ));
        }
        responseParams.add(fhir.ParametersParameter(
          name: fhir.FhirString('property'),
          part_: propParts,
        ));
      }
    }

    final result = fhir.Parameters(parameter: responseParams);
    FhirantLogging()
        .logInfo('Lookup found code "$effectiveCode" in CodeSystem');
    return Response.ok(
      result.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('Terminology \$lookup failed', e, stackTrace);
    return _errorResponse(500, 'Internal error: $e');
  }
}

/// Handler for ValueSet/$expand.
///
/// Expands a ValueSet by resolving compose.include rules against stored
/// CodeSystems. Supports both instance-level (ValueSet/<id>/$expand) and
/// type-level (ValueSet/$expand?url=...) invocation.
///
/// Parameters: url, filter, offset, count.
Future<Response> expandHandler(
  Request request,
  FhirAntDb dbInterface, [
  String? id,
]) async {
  try {
    final params = await _extractOperationParams(request);

    final url = params['url'] as String?;
    final filter = params['filter'] as String?;
    final offsetStr = params['offset'] as String?;
    final countStr = params['count'] as String?;
    final offset = offsetStr != null ? int.tryParse(offsetStr) : null;
    final count = countStr != null ? int.tryParse(countStr) : null;

    // Find the ValueSet
    fhir.ValueSet? valueSet;
    if (id != null) {
      final resource =
          await dbInterface.getResource(fhir.R4ResourceType.ValueSet, id);
      if (resource == null) {
        return _errorResponse(404, 'ValueSet/$id not found');
      }
      valueSet = resource as fhir.ValueSet;
    } else if (url != null) {
      valueSet = await _findValueSetByUrl(url, dbInterface);
      if (valueSet == null) {
        return _errorResponse(404, 'ValueSet not found: $url');
      }
    } else {
      return _errorResponse(
          400, 'Parameter "url" is required for type-level \$expand');
    }

    // If already has an expansion, optionally filter it
    if (valueSet.expansion?.contains != null &&
        valueSet.expansion!.contains!.isNotEmpty) {
      var contains = valueSet.expansion!.contains!;
      if (filter != null && filter.isNotEmpty) {
        contains = _filterContains(contains, filter);
      }
      final total = contains.length;
      if (offset != null && offset > 0) {
        contains =
            contains.skip(offset).toList();
      }
      if (count != null) {
        contains = contains.take(count).toList();
      }
      final expanded = valueSet.copyWith(
        expansion: fhir.ValueSetExpansion(
          timestamp: DateTime.now().toFhirDateTime,
          total: fhir.FhirInteger(total),
          offset: offset != null ? fhir.FhirInteger(offset) : null,
          contains: contains,
        ),
      );
      return Response.ok(
        expanded.toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Expand from compose.include
    final allContains = <fhir.ValueSetContains>[];
    if (valueSet.compose?.include != null) {
      for (final include in valueSet.compose!.include) {
        final includeSystem = include.system?.valueString;

        if (include.concept != null && include.concept!.isNotEmpty) {
          // Explicit concept list
          for (final c in include.concept!) {
            allContains.add(fhir.ValueSetContains(
              system: includeSystem != null
                  ? fhir.FhirUri(includeSystem)
                  : null,
              code: c.code,
              display: c.display,
            ));
          }
        } else if (includeSystem != null) {
          // Include all codes from the CodeSystem
          final cs =
              await _findCodeSystemByUrl(includeSystem, dbInterface);
          if (cs != null && cs.concept != null) {
            _flattenConcepts(cs.concept!, includeSystem, allContains);
          }
        }

        // Apply filter from include rules (ValueSet.compose.include.filter)
        // These are CodeSystem-level filters, not the $expand filter param.
        // For simplicity, we don't apply compose-level filters here —
        // full filter support requires property-based CodeSystem filtering.
      }
    }

    // Apply exclude rules
    if (valueSet.compose?.exclude != null) {
      for (final exclude in valueSet.compose!.exclude!) {
        final excludeSystem = exclude.system?.valueString;
        if (exclude.concept != null) {
          for (final c in exclude.concept!) {
            allContains.removeWhere((entry) =>
                entry.code?.valueString == c.code.valueString &&
                (excludeSystem == null ||
                    entry.system?.valueString == excludeSystem));
          }
        }
      }
    }

    // Apply $expand filter parameter (text match on display/code)
    var filtered = allContains;
    if (filter != null && filter.isNotEmpty) {
      filtered = _filterContains(filtered, filter);
    }

    final total = filtered.length;
    if (offset != null && offset > 0) {
      filtered = filtered.skip(offset).toList();
    }
    if (count != null) {
      filtered = filtered.take(count).toList();
    }

    final expanded = valueSet.copyWith(
      expansion: fhir.ValueSetExpansion(
        timestamp: DateTime.now().toFhirDateTime,
        total: fhir.FhirInteger(total),
        offset: offset != null ? fhir.FhirInteger(offset) : null,
        contains: filtered,
      ),
    );

    FhirantLogging().logInfo(
        'Expanded ValueSet with ${filtered.length} concepts');
    return Response.ok(
      expanded.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('Terminology \$expand failed', e, stackTrace);
    return _errorResponse(500, 'Internal error: $e');
  }
}

/// Flatten a hierarchical CodeSystem concept list into ValueSetContains entries.
void _flattenConcepts(
  List<fhir.CodeSystemConcept> concepts,
  String system,
  List<fhir.ValueSetContains> out,
) {
  for (final c in concepts) {
    out.add(fhir.ValueSetContains(
      system: fhir.FhirUri(system),
      code: c.code,
      display: c.display,
    ));
    if (c.concept != null) {
      _flattenConcepts(c.concept!, system, out);
    }
  }
}

/// Filter ValueSetContains entries by a text filter (case-insensitive match
/// on display or code).
List<fhir.ValueSetContains> _filterContains(
  List<fhir.ValueSetContains> contains,
  String filter,
) {
  final lowerFilter = filter.toLowerCase();
  return contains.where((entry) {
    final display = entry.display?.valueString?.toLowerCase() ?? '';
    final code = entry.code?.valueString?.toLowerCase() ?? '';
    return display.contains(lowerFilter) || code.contains(lowerFilter);
  }).toList();
}

// ── Private helpers ────────────────────────────────────────────────────

/// Extract operation parameters from GET query params or POST body.
Future<Map<String, dynamic>> _extractOperationParams(Request request) async {
  if (request.method == 'GET') {
    return Map<String, dynamic>.from(request.url.queryParameters);
  }

  // POST: try Parameters resource first, then form-encoded
  final body = await request.readAsString();
  if (body.isEmpty) return {};

  try {
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (json['resourceType'] == 'Parameters') {
      return _parseParametersResource(json);
    }
    // Might be a raw Coding or other JSON
    return json;
  } catch (_) {
    // Fall back to form-encoded
    return Map<String, dynamic>.from(Uri.splitQueryString(body));
  }
}

/// Parse a Parameters resource into a flat map of name→value.
Map<String, dynamic> _parseParametersResource(Map<String, dynamic> json) {
  final result = <String, dynamic>{};
  final params = json['parameter'] as List<dynamic>?;
  if (params == null) return result;

  for (final p in params) {
    final param = p as Map<String, dynamic>;
    final name = param['name'] as String?;
    if (name == null) continue;

    // Check for typed value fields
    for (final key in param.keys) {
      if (key.startsWith('value')) {
        result[name] = param[key];
        break;
      }
    }
    // Check for resource
    if (param.containsKey('resource')) {
      result[name] = param['resource'];
    }
  }
  return result;
}

/// Find a CodeSystem by its canonical URL.
Future<fhir.CodeSystem?> _findCodeSystemByUrl(
    String url, FhirAntDb dbInterface) async {
  final results = await dbInterface.search(
    resourceType: fhir.R4ResourceType.CodeSystem,
    searchParameters: {'url': [url]},
    count: 1,
  );
  if (results.isEmpty) return null;
  return results.first as fhir.CodeSystem;
}

/// Find a ValueSet by its canonical URL.
Future<fhir.ValueSet?> _findValueSetByUrl(
    String url, FhirAntDb dbInterface) async {
  final results = await dbInterface.search(
    resourceType: fhir.R4ResourceType.ValueSet,
    searchParameters: {'url': [url]},
    count: 1,
  );
  if (results.isEmpty) return null;
  return results.first as fhir.ValueSet;
}

/// Recursively find a concept by code in a hierarchical concept list.
fhir.CodeSystemConcept? _findConcept(
    List<fhir.CodeSystemConcept>? concepts, String code) {
  if (concepts == null) return null;
  for (final concept in concepts) {
    if (concept.code.valueString == code) return concept;
    final child = _findConcept(concept.concept, code);
    if (child != null) return child;
  }
  return null;
}

/// Validate a code against a CodeSystem.
Response _validateAgainstCodeSystem(
  fhir.CodeSystem codeSystem,
  String code,
  String? system,
  String? display,
) {
  // Verify system matches if provided
  final csUrl = codeSystem.url?.valueString;
  if (system != null && csUrl != null && system != csUrl) {
    return _validationResult(
      result: false,
      message:
          'System "$system" does not match CodeSystem URL "$csUrl"',
    );
  }

  final concept = _findConcept(codeSystem.concept, code);
  if (concept == null) {
    return _validationResult(
      result: false,
      message:
          'Code "$code" not found in CodeSystem ${csUrl ?? ''}',
    );
  }

  // Optionally validate display
  if (display != null && concept.display?.valueString != null) {
    if (display != concept.display!.valueString) {
      return _validationResult(
        result: true,
        message:
            'Code found but display does not match. '
            'Expected "${concept.display!.valueString}", got "$display"',
        display: concept.display!.valueString,
      );
    }
  }

  return _validationResult(
    result: true,
    display: concept.display?.valueString,
  );
}

/// Validate a code against a ValueSet.
Future<Response> _validateAgainstValueSet(
  fhir.ValueSet valueSet,
  String code,
  String? system,
  String? display,
  FhirAntDb dbInterface,
) async {
  // 1. Check pre-computed expansion first
  if (valueSet.expansion?.contains != null) {
    final found = _findInExpansion(valueSet.expansion!.contains!, code, system);
    if (found != null) {
      final foundDisplay = found.display?.valueString;
      if (display != null && foundDisplay != null && display != foundDisplay) {
        return _validationResult(
          result: true,
          message: 'Code found but display does not match',
          display: foundDisplay,
        );
      }
      return _validationResult(result: true, display: foundDisplay);
    }
    // Expansion is authoritative — if not found there, it's invalid
    return _validationResult(
      result: false,
      message: 'Code "$code" not found in ValueSet expansion',
    );
  }

  // 2. Check compose.include rules
  if (valueSet.compose?.include != null) {
    for (final include in valueSet.compose!.include) {
      // Check if system matches
      final includeSystem = include.system?.valueString;
      if (system != null && includeSystem != null && system != includeSystem) {
        continue;
      }

      // Check explicitly listed concepts
      if (include.concept != null) {
        for (final c in include.concept!) {
          if (c.code.valueString == code) {
            final foundDisplay = c.display?.valueString;
            if (display != null &&
                foundDisplay != null &&
                display != foundDisplay) {
              return _validationResult(
                result: true,
                message: 'Code found but display does not match',
                display: foundDisplay,
              );
            }
            return _validationResult(result: true, display: foundDisplay);
          }
        }
      }

      // If no explicit concepts and system matches, check the CodeSystem
      if (include.concept == null && includeSystem != null) {
        final cs = await _findCodeSystemByUrl(includeSystem, dbInterface);
        if (cs != null) {
          final concept = _findConcept(cs.concept, code);
          if (concept != null) {
            return _validationResult(
              result: true,
              display: concept.display?.valueString,
            );
          }
        }
      }
    }

    // Check exclude rules
    // (If we got here, the code wasn't found in any include rule)
  }

  return _validationResult(
    result: false,
    message: 'Code "$code" not found in ValueSet '
        '${valueSet.url?.valueString ?? ''}',
  );
}

/// Recursively find a code in a ValueSet expansion.
fhir.ValueSetContains? _findInExpansion(
  List<fhir.ValueSetContains> contains,
  String code,
  String? system,
) {
  for (final entry in contains) {
    if (entry.code?.valueString == code) {
      if (system == null || entry.system?.valueString == system) {
        return entry;
      }
    }
    if (entry.contains != null) {
      final child = _findInExpansion(entry.contains!, code, system);
      if (child != null) return child;
    }
  }
  return null;
}

/// Build a Parameters response for $validate-code.
Response _validationResult({
  required bool result,
  String? message,
  String? display,
}) {
  final params = <fhir.ParametersParameter>[
    fhir.ParametersParameter(
      name: fhir.FhirString('result'),
      valueBoolean: fhir.FhirBoolean(result),
    ),
  ];

  if (message != null) {
    params.add(fhir.ParametersParameter(
      name: fhir.FhirString('message'),
      valueString: fhir.FhirString(message),
    ));
  }

  if (display != null) {
    params.add(fhir.ParametersParameter(
      name: fhir.FhirString('display'),
      valueString: fhir.FhirString(display),
    ));
  }

  final response = fhir.Parameters(parameter: params);
  return Response.ok(
    response.toJsonString(),
    headers: {'Content-Type': 'application/json'},
  );
}

Response _errorResponse(int statusCode, String message) {
  return Response(
    statusCode,
    body: jsonEncode({
      'resourceType': 'OperationOutcome',
      'issue': [
        {
          'severity': 'error',
          'code': statusCode == 404 ? 'not-found' : 'invalid',
          'diagnostics': message,
        }
      ]
    }),
    headers: {'Content-Type': 'application/json'},
  );
}
