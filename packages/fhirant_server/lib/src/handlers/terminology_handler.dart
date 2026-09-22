import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/utils/canonical.dart';
import 'package:fhirant_server/src/utils/operation_outcomes.dart';
import 'package:fhirant_server/src/utils/parameters_body.dart';
import 'package:fhirant_server/src/utils/stored_resource.dart';
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
    final params = await readOperationParameters(request);

    final code = params['code'] as String?;
    final system = params['system'] as String?;
    final display = params['display'] as String?;
    final url = params['url'] as String?;
    final coding = params['coding'] as Map<String, dynamic>?;

    // Extract code/system from coding if provided
    final effectiveCode = code ?? (coding?['code'] as String?);
    final effectiveSystem = system ?? (coding?['system'] as String?);

    if (effectiveCode == null) {
      return outcome(
        400,
        fhir.IssueType.invalid,
        'Parameter "code" or "coding" is required',
      );
    }

    // Instance-level: validate against specific resource
    if (id != null && resourceType != null) {
      final lookup = await lookupStored(request, dbInterface, resourceType, id);
      if (lookup is! StoredFound) return lookupRefusal(lookup);
      final resource = lookup.resource;

      if (resourceType == 'CodeSystem' && resource is fhir.CodeSystem) {
        return _validateAgainstCodeSystem(
          resource,
          effectiveCode,
          effectiveSystem,
          display,
        );
      } else if (resourceType == 'ValueSet' && resource is fhir.ValueSet) {
        return await _validateAgainstValueSet(
          resource,
          effectiveCode,
          effectiveSystem,
          display,
          dbInterface,
        );
      }
      return outcome(
        400,
        fhir.IssueType.invalid,
        r'$validate-code only supported for CodeSystem and ValueSet',
      );
    }

    // Type-level or system-level: look up by URL/system
    if (resourceType == 'CodeSystem' || (resourceType == null && url == null)) {
      if (effectiveSystem == null && url == null) {
        return outcome(
          400,
          fhir.IssueType.invalid,
          'Parameter "system" or "url" is required for CodeSystem',
        );
      }
      final lookupUrl = url ?? effectiveSystem;
      final codeSystem = await findOneByCanonical<fhir.CodeSystem>(
        dbInterface,
        fhir.R4ResourceType.CodeSystem,
        lookupUrl!,
      );
      if (codeSystem == null) {
        // "Not held" is not "not valid" (REVIEW-2026-09-17 T1). R4B
        // codesystem-operation-validate-code.html, read whole 2026-09-17,
        // heads its error example, verbatim: "An error like this not
        // returned if the code is not valid, but when the server is unable
        // to determine whether the code is valid".
        return outcome(
            404,
            fhir.IssueType.notFound,
            'CodeSystem $lookupUrl is not held by this server, so the code '
            'cannot be validated');
      }
      return _validateAgainstCodeSystem(
        codeSystem,
        effectiveCode,
        effectiveSystem,
        display,
      );
    }

    if (resourceType == 'ValueSet') {
      if (url == null) {
        return outcome(
          400,
          fhir.IssueType.invalid,
          'Parameter "url" is required for ValueSet',
        );
      }
      final valueSet = await findOneByCanonical<fhir.ValueSet>(
        dbInterface,
        fhir.R4ResourceType.ValueSet,
        url,
      );
      if (valueSet == null) {
        return outcome(
            404,
            fhir.IssueType.notFound,
            'ValueSet $url is not held by this server, so the code cannot be '
            'validated');
      }
      return await _validateAgainstValueSet(
        valueSet,
        effectiveCode,
        effectiveSystem,
        display,
        dbInterface,
      );
    }

    return outcome(
      400,
      fhir.IssueType.invalid,
      'Unable to determine target for validation',
    );
  } catch (e, stackTrace) {
    FhirantLogging()
        .logError(r'Terminology $validate-code failed', e, stackTrace);
    return outcome(500, fhir.IssueType.invalid, 'Internal error');
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
    final params = await readOperationParameters(request);

    final code = params['code'] as String?;
    final system = params['system'] as String?;
    final coding = params['coding'] as Map<String, dynamic>?;

    final effectiveCode = code ?? (coding?['code'] as String?);
    final effectiveSystem = system ?? (coding?['system'] as String?);

    if (effectiveCode == null) {
      return outcome(
        400,
        fhir.IssueType.invalid,
        'Parameter "code" or "coding" is required',
      );
    }

    // Instance-level: lookup in specific CodeSystem
    fhir.CodeSystem? codeSystem;
    if (id != null) {
      final lookup = await lookupStored(request, dbInterface, 'CodeSystem', id);
      if (lookup is! StoredFound) return lookupRefusal(lookup);
      codeSystem = lookup.resource as fhir.CodeSystem;
    } else {
      // Type-level: find by system URL
      if (effectiveSystem == null) {
        return outcome(
          400,
          fhir.IssueType.invalid,
          'Parameter "system" or "coding.system" is required',
        );
      }
      codeSystem = await findOneByCanonical<fhir.CodeSystem>(
        dbInterface,
        fhir.R4ResourceType.CodeSystem,
        effectiveSystem,
      );
      if (codeSystem == null) {
        return outcome(
          404,
          fhir.IssueType.notFound,
          'CodeSystem not found: $effectiveSystem',
        );
      }
    }

    // Find the concept in the code system
    final concept = _findConcept(codeSystem.concept, effectiveCode);
    if (concept == null) {
      final systemName =
          codeSystem.url?.valueString ?? codeSystem.id?.toString() ?? 'unknown';
      return outcome(
        404,
        fhir.IssueType.notFound,
        'Code "$effectiveCode" not found in CodeSystem $systemName',
      );
    }

    // Build response Parameters
    final responseParams = <fhir.ParametersParameter>[
      fhir.ParametersParameter(
        name: fhir.FhirString('name'),
        valueString: fhir.FhirString(
          codeSystem.name?.valueString ?? codeSystem.title?.valueString ?? '',
        ),
      ),
      fhir.ParametersParameter(
        name: fhir.FhirString('display'),
        valueString: fhir.FhirString(concept.display?.valueString ?? ''),
      ),
    ];

    if (codeSystem.version?.valueString != null) {
      responseParams.add(
        fhir.ParametersParameter(
          name: fhir.FhirString('version'),
          valueString: codeSystem.version,
        ),
      );
    }

    if (concept.definition?.valueString != null) {
      responseParams.add(
        fhir.ParametersParameter(
          name: fhir.FhirString('definition'),
          valueString: concept.definition,
        ),
      );
    }

    // Add designations
    if (concept.designation != null) {
      for (final d in concept.designation!) {
        responseParams.add(
          fhir.ParametersParameter(
            name: fhir.FhirString('designation'),
            part_: [
              if (d.language != null)
                fhir.ParametersParameter(
                  name: fhir.FhirString('language'),
                  valueCode: d.language,
                ),
              if (d.use != null)
                fhir.ParametersParameter(
                  name: fhir.FhirString('use'),
                  valueCoding: d.use,
                ),
              fhir.ParametersParameter(
                name: fhir.FhirString('value'),
                valueString: d.value,
              ),
            ],
          ),
        );
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
          propParts.add(
            fhir.ParametersParameter(
              name: fhir.FhirString('value'),
              valueCode: fhir.FhirCode(propJson['valueCode'] as String),
            ),
          );
        } else if (propJson.containsKey('valueString')) {
          propParts.add(
            fhir.ParametersParameter(
              name: fhir.FhirString('value'),
              valueString: fhir.FhirString(propJson['valueString'] as String),
            ),
          );
        } else if (propJson.containsKey('valueBoolean')) {
          propParts.add(
            fhir.ParametersParameter(
              name: fhir.FhirString('value'),
              valueBoolean: fhir.FhirBoolean(propJson['valueBoolean'] as bool),
            ),
          );
        } else if (propJson.containsKey('valueInteger')) {
          propParts.add(
            fhir.ParametersParameter(
              name: fhir.FhirString('value'),
              valueInteger: fhir.FhirInteger(propJson['valueInteger'] as int),
            ),
          );
        }
        responseParams.add(
          fhir.ParametersParameter(
            name: fhir.FhirString('property'),
            part_: propParts,
          ),
        );
      }
    }

    final result = fhir.Parameters(parameter: responseParams);
    FhirantLogging().logInfo('Lookup resolved a code in CodeSystem');
    return Response.ok(
      result.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError(r'Terminology $lookup failed', e, stackTrace);
    return outcome(500, fhir.IssueType.invalid, 'Internal error');
  }
}

/// Handler for ValueSet/$expand.
///
/// Expands a ValueSet by resolving compose.include rules against stored
/// CodeSystems. Supports both instance-level (ValueSet/`<id>`/$expand) and
/// type-level (ValueSet/$expand?url=...) invocation.
///
/// Parameters: url, filter, offset, count.
Future<Response> expandHandler(
  Request request,
  FhirAntDb dbInterface, [
  String? id,
]) async {
  try {
    final params = await readOperationParameters(request);

    final url = params['url'] as String?;
    final filter = params['filter'] as String?;
    final valueSetVersion =
        params['valueSetVersion'] as String? ?? params['version'] as String?;
    final offsetStr = params['offset'] as String?;
    final countStr = params['count'] as String?;
    final offset = offsetStr != null ? int.tryParse(offsetStr) : null;
    final count = countStr != null ? int.tryParse(countStr) : null;

    // Find the ValueSet
    fhir.ValueSet? valueSet;
    if (id != null) {
      final lookup = await lookupStored(request, dbInterface, 'ValueSet', id);
      if (lookup is! StoredFound) return lookupRefusal(lookup);
      valueSet = lookup.resource as fhir.ValueSet;
    } else if (url != null) {
      valueSet = await findOneByCanonical<fhir.ValueSet>(
        dbInterface,
        fhir.R4ResourceType.ValueSet,
        url,
      );
      if (valueSet == null) {
        return outcome(
          404,
          fhir.IssueType.notFound,
          'ValueSet not found: $url',
        );
      }
    } else {
      return outcome(
        400,
        fhir.IssueType.invalid,
        r'Parameter "url" is required for type-level $expand',
      );
    }

    // Check version if specified
    if (valueSetVersion != null) {
      final vsVersion = valueSet.version?.valueString;
      if (vsVersion == null || vsVersion != valueSetVersion) {
        return outcome(
            404,
            fhir.IssueType.notFound,
            'ValueSet version "$valueSetVersion" not found'
            '${vsVersion != null ? ' (available: $vsVersion)' : ''}');
      }
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
        contains = contains.skip(offset).toList();
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

    // The compose, expanded by the store: the one implementation, which
    // `:in`, `:not-in` and `$validate-code` use too, and which refuses what
    // it cannot evaluate rather than answering from the parts it can
    // (REVIEW-2026-09-06 finding 24, REVIEW-2026-09-17 T1 and T2).
    final List<ExpandedCode> codes;
    try {
      codes = await dbInterface.fhirDao.expandValueSet(valueSet);
    } on ValueSetRefusal catch (e) {
      return outcome(422, issueTypeOfCode(e.issueCode), e.message);
    }
    final allContains = [
      for (final c in codes)
        fhir.ValueSetContains(
          system: c.system != null ? fhir.FhirUri(c.system) : null,
          code: fhir.FhirCode(c.code),
          display: c.display != null ? fhir.FhirString(c.display) : null,
        ),
    ];

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

    FhirantLogging()
        .logInfo('Expanded ValueSet with ${filtered.length} concepts');
    return Response.ok(
      expanded.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError(r'Terminology $expand failed', e, stackTrace);
    return outcome(500, fhir.IssueType.invalid, 'Internal error');
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

/// Recursively find a concept by code in a hierarchical concept list.
fhir.CodeSystemConcept? _findConcept(
  List<fhir.CodeSystemConcept>? concepts,
  String code,
) {
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
      message: 'System "$system" does not match CodeSystem URL "$csUrl"',
    );
  }

  final concept = _findConcept(codeSystem.concept, code);
  if (concept == null) {
    // A code missing from a CodeSystem held in part (content other than
    // complete) is not thereby invalid: the server cannot tell.
    final content = codeSystem.content.toString();
    if (content != 'complete') {
      return outcome(
          422,
          fhir.IssueType.notSupported,
          'CodeSystem ${csUrl ?? ''} is held with content "$content", not '
          'the complete code system, so a code it does not list cannot be '
          'called invalid');
    }
    return _validationResult(
      result: false,
      message: 'Code "$code" not found in CodeSystem ${csUrl ?? ''}',
    );
  }

  // Optionally validate display
  if (display != null && concept.display?.valueString != null) {
    if (display != concept.display!.valueString) {
      return _validationResult(
        result: true,
        message: 'Code found but display does not match. '
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

  // 2. The compose, expanded by the store, as `$expand` and `:in` expand
  // it. This used to walk the includes itself and return on the first
  // match, so a code the compose excludes validated true
  // (REVIEW-2026-09-17 T2).
  final List<ExpandedCode> codes;
  try {
    codes = await dbInterface.fhirDao.expandValueSet(valueSet);
  } on ValueSetRefusal catch (e) {
    return outcome(422, issueTypeOfCode(e.issueCode), e.message);
  }
  for (final c in codes) {
    if (c.code != code) continue;
    if (system != null && c.system != null && system != c.system) continue;
    if (display != null && c.display != null && display != c.display) {
      return _validationResult(
        result: true,
        message: 'Code found but display does not match',
        display: c.display,
      );
    }
    return _validationResult(result: true, display: c.display);
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
    params.add(
      fhir.ParametersParameter(
        name: fhir.FhirString('message'),
        valueString: fhir.FhirString(message),
      ),
    );
  }

  if (display != null) {
    params.add(
      fhir.ParametersParameter(
        name: fhir.FhirString('display'),
        valueString: fhir.FhirString(display),
      ),
    );
  }

  final response = fhir.Parameters(parameter: params);
  return Response.ok(
    response.toJsonString(),
    headers: {'Content-Type': 'application/json'},
  );
}

// ── NamingSystem $preferred-id ─────────────────────────────────────────

/// Handler for NamingSystem/$preferred-id.
///
/// Returns the preferred identifier of the requested type for a NamingSystem.
/// Parameters: id (NamingSystem id or name), type (oid|uri|uuid|other).
Future<Response> preferredIdHandler(
  Request request,
  FhirAntDb dbInterface,
) async {
  try {
    final params = await readOperationParameters(request);

    final id = params['id'] as String?;
    final type = params['type'] as String?;

    if (id == null) {
      return outcome(400, fhir.IssueType.invalid, 'Parameter "id" is required');
    }
    if (type == null) {
      return outcome(
        400,
        fhir.IssueType.invalid,
        'Parameter "type" is required',
      );
    }

    // Try to find the NamingSystem by resource id first, then by name
    fhir.NamingSystem? namingSystem;
    final byId =
        await dbInterface.getResource(fhir.R4ResourceType.NamingSystem, id);
    if (byId != null && byId is fhir.NamingSystem) {
      namingSystem = byId;
    } else {
      // Search by name
      final results = await dbInterface.search(
        resourceType: fhir.R4ResourceType.NamingSystem,
        searchParameters: {
          'name': [id],
        },
        count: 1,
      );
      if (results.isNotEmpty && results.first is fhir.NamingSystem) {
        namingSystem = results.first as fhir.NamingSystem;
      }
    }

    if (namingSystem == null) {
      return outcome(
        404,
        fhir.IssueType.notFound,
        'NamingSystem not found: $id',
      );
    }

    // Find the uniqueId entry matching the requested type.
    // Prefer entries with preferred=true.
    fhir.NamingSystemUniqueId? match;
    fhir.NamingSystemUniqueId? preferredMatch;

    for (final uid in namingSystem.uniqueId) {
      if (uid.type.valueString == type) {
        match ??= uid;
        if (uid.preferred?.valueBoolean == true) {
          preferredMatch = uid;
        }
      }
    }

    final chosen = preferredMatch ?? match;
    if (chosen == null) {
      return outcome(
        404,
        fhir.IssueType.notFound,
        'No uniqueId of type "$type" found in NamingSystem',
      );
    }

    final result = fhir.Parameters(
      parameter: [
        fhir.ParametersParameter(
          name: fhir.FhirString('result'),
          valueString: chosen.value,
        ),
      ],
    );

    FhirantLogging().logInfo('NamingSystem \$preferred-id: found $type');
    return Response.ok(
      result.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging()
        .logError(r'Terminology $preferred-id failed', e, stackTrace);
    return outcome(500, fhir.IssueType.invalid, 'Internal error');
  }
}

// ── ConceptMap $translate ──────────────────────────────────────────────

/// Handler for ConceptMap/$translate.
///
/// Translates a code from one value set to another using a ConceptMap.
/// Parameters: code, system, source, target, coding, url.
Future<Response> translateHandler(
  Request request,
  FhirAntDb dbInterface, [
  String? id,
]) async {
  try {
    final params = await readOperationParameters(request);

    final code = params['code'] as String?;
    final system = params['system'] as String?;
    final source = params['source'] as String?;
    final target = params['target'] as String?;
    final url = params['url'] as String?;
    final coding = params['coding'] as Map<String, dynamic>?;

    final effectiveCode = code ?? (coding?['code'] as String?);
    final effectiveSystem = system ?? (coding?['system'] as String?);

    if (effectiveCode == null) {
      return outcome(
        400,
        fhir.IssueType.invalid,
        'Parameter "code" or "coding" is required',
      );
    }

    // Find the ConceptMap
    fhir.ConceptMap? conceptMap;
    if (id != null) {
      final lookup = await lookupStored(request, dbInterface, 'ConceptMap', id);
      if (lookup is! StoredFound) return lookupRefusal(lookup);
      conceptMap = lookup.resource as fhir.ConceptMap;
    } else if (url != null) {
      conceptMap = await findOneByCanonical<fhir.ConceptMap>(
        dbInterface,
        fhir.R4ResourceType.ConceptMap,
        url,
      );
    } else if (source != null || target != null) {
      // Search by source and/or target
      final searchParams = <String, List<String>>{};
      if (source != null) searchParams['source'] = [source];
      if (target != null) searchParams['target'] = [target];
      final results = await dbInterface.search(
        resourceType: fhir.R4ResourceType.ConceptMap,
        searchParameters: searchParams,
        count: 1,
      );
      if (results.isNotEmpty && results.first is fhir.ConceptMap) {
        conceptMap = results.first as fhir.ConceptMap;
      }
    }

    if (conceptMap == null) {
      return outcome(404, fhir.IssueType.notFound, 'ConceptMap not found');
    }

    // Every target of every element for the code, across the groups whose
    // source system matches. OperationDefinition ConceptMap-translate
    // (bundled profiles-resources.ndjson, verbatim): `match` is 0..*, "Note
    // that there may be multiple matches of equal or differing equivalence,
    // and the matches may include equivalence values that mean that there
    // is no match"; `result` is "True if the concept could be translated
    // successfully. The value can only be true if at least one returned
    // match has an equivalence which is not unmatched or disjoint". This
    // used to answer with the first target alone (REVIEW-2026-09-17 C7).
    final matches = <fhir.ParametersParameter>[];
    var translated = false;
    for (final group in conceptMap.group ?? const <fhir.ConceptMapGroup>[]) {
      final groupSource = group.source?.valueString;
      if (effectiveSystem != null &&
          groupSource != null &&
          effectiveSystem != groupSource) {
        continue;
      }
      for (final element in group.element) {
        if (element.code?.valueString != effectiveCode) continue;
        for (final t in element.target ?? const <fhir.ConceptMapTarget>[]) {
          final equivalence = t.equivalence.valueString ?? 'equivalent';
          if (equivalence != 'unmatched' && equivalence != 'disjoint') {
            translated = true;
          }
          matches.add(
            fhir.ParametersParameter(
              name: fhir.FhirString('match'),
              part_: [
                fhir.ParametersParameter(
                  name: fhir.FhirString('equivalence'),
                  valueCode: fhir.FhirCode(equivalence),
                ),
                if (t.code != null)
                  fhir.ParametersParameter(
                    name: fhir.FhirString('concept'),
                    valueCoding: fhir.Coding(
                      system: group.target,
                      code: t.code,
                      display: t.display,
                    ),
                  ),
                for (final p in t.product ?? const <fhir.ConceptMapDependsOn>[])
                  fhir.ParametersParameter(
                    name: fhir.FhirString('product'),
                    part_: [
                      fhir.ParametersParameter(
                        name: fhir.FhirString('element'),
                        valueUri: p.property,
                      ),
                      fhir.ParametersParameter(
                        name: fhir.FhirString('concept'),
                        valueCoding: fhir.Coding(
                          system: p.system,
                          code: p.value.valueString?.toFhirCode,
                          display: p.display,
                        ),
                      ),
                    ],
                  ),
                if (conceptMap.url?.valueString case final String source)
                  fhir.ParametersParameter(
                    name: fhir.FhirString('source'),
                    valueUri: fhir.FhirUri(source),
                  ),
              ],
            ),
          );
        }
      }
    }

    final result = fhir.Parameters(
      parameter: [
        fhir.ParametersParameter(
          name: fhir.FhirString('result'),
          valueBoolean: fhir.FhirBoolean(translated),
        ),
        ...matches,
      ],
    );
    FhirantLogging().logInfo(
      r'ConceptMap $translate: ' '${matches.length} match(es)',
    );
    return Response.ok(
      result.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError(r'Terminology $translate failed', e, stackTrace);
    return outcome(500, fhir.IssueType.invalid, 'Internal error');
  }
}

// ── CodeSystem $subsumes ───────────────────────────────────────────────

/// Handler for CodeSystem/$subsumes.
///
/// Tests the subsumption relationship between two codes.
/// Parameters: codeA, codeB, system, codingA, codingB.
Future<Response> subsumesHandler(
  Request request,
  FhirAntDb dbInterface, [
  String? id,
]) async {
  try {
    final params = await readOperationParameters(request);

    final codeA = params['codeA'] as String?;
    final codeB = params['codeB'] as String?;
    final system = params['system'] as String?;
    final codingA = params['codingA'] as Map<String, dynamic>?;
    final codingB = params['codingB'] as Map<String, dynamic>?;

    final effectiveCodeA = codeA ?? (codingA?['code'] as String?);
    final effectiveCodeB = codeB ?? (codingB?['code'] as String?);
    final effectiveSystem = system ??
        (codingA?['system'] as String?) ??
        (codingB?['system'] as String?);

    if (effectiveCodeA == null || effectiveCodeB == null) {
      return outcome(
          400,
          fhir.IssueType.invalid,
          'Parameters "codeA" and "codeB" (or "codingA"/"codingB") '
          'are required');
    }

    // Find the CodeSystem
    fhir.CodeSystem? codeSystem;
    if (id != null) {
      final lookup = await lookupStored(request, dbInterface, 'CodeSystem', id);
      if (lookup is! StoredFound) return lookupRefusal(lookup);
      codeSystem = lookup.resource as fhir.CodeSystem;
    } else if (effectiveSystem != null) {
      codeSystem = await findOneByCanonical<fhir.CodeSystem>(
        dbInterface,
        fhir.R4ResourceType.CodeSystem,
        effectiveSystem,
      );
      if (codeSystem == null) {
        return outcome(
          404,
          fhir.IssueType.notFound,
          'CodeSystem not found: $effectiveSystem',
        );
      }
    } else {
      return outcome(
        400,
        fhir.IssueType.invalid,
        'Parameter "system" is required when no id is provided',
      );
    }

    // Verify both codes exist in the CodeSystem
    final conceptA = _findConcept(codeSystem.concept, effectiveCodeA);
    if (conceptA == null) {
      return outcome(
        400,
        fhir.IssueType.invalid,
        'Code "$effectiveCodeA" not found in CodeSystem',
      );
    }
    final conceptB = _findConcept(codeSystem.concept, effectiveCodeB);
    if (conceptB == null) {
      return outcome(
        400,
        fhir.IssueType.invalid,
        'Code "$effectiveCodeB" not found in CodeSystem',
      );
    }

    // Determine subsumption relationship
    String relation;
    if (effectiveCodeA == effectiveCodeB) {
      relation = 'equivalent';
    } else if (_isAncestor(
      codeSystem.concept,
      effectiveCodeA,
      effectiveCodeB,
    )) {
      relation = 'subsumes';
    } else if (_isAncestor(
      codeSystem.concept,
      effectiveCodeB,
      effectiveCodeA,
    )) {
      relation = 'subsumed-by';
    } else {
      relation = 'not-subsumed';
    }

    final result = fhir.Parameters(
      parameter: [
        fhir.ParametersParameter(
          name: fhir.FhirString('outcome'),
          valueCode: fhir.FhirCode(relation),
        ),
      ],
    );

    FhirantLogging().logInfo(
      'CodeSystem \$subsumes: $relation',
    );
    return Response.ok(
      result.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError(r'Terminology $subsumes failed', e, stackTrace);
    return outcome(500, fhir.IssueType.invalid, 'Internal error');
  }
}

/// Check if [ancestor] is an ancestor of [descendant] in the concept
/// hierarchy. Returns true if [descendant] appears somewhere under
/// the subtree rooted at [ancestor].
bool _isAncestor(
  List<fhir.CodeSystemConcept>? concepts,
  String ancestor,
  String descendant,
) {
  if (concepts == null) return false;
  for (final concept in concepts) {
    if (concept.code.valueString == ancestor) {
      // ancestor found — check if descendant is in its subtree
      return _containsCode(concept.concept, descendant);
    }
    // Recurse into children
    if (_isAncestor(concept.concept, ancestor, descendant)) {
      return true;
    }
  }
  return false;
}

/// Check if [code] exists anywhere in the given concept tree.
bool _containsCode(List<fhir.CodeSystemConcept>? concepts, String code) {
  if (concepts == null) return false;
  for (final concept in concepts) {
    if (concept.code.valueString == code) return true;
    if (_containsCode(concept.concept, code)) return true;
  }
  return false;
}
