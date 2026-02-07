/// Utility for shaping FHIR resource responses based on _summary and _elements parameters.
class FhirResponseShaper {
  static const _subsettedTag = {
    'system':
        'http://terminology.hl7.org/CodeSystem/v3-ObservationValue',
    'code': 'SUBSETTED',
    'display': 'subsetted',
  };

  /// Shape a resource JSON according to the _summary mode.
  ///
  /// Modes:
  /// - `text`: keep resourceType, id, meta, text only
  /// - `data`: remove text field
  /// - `true`: same as text (full isSummary requires StructureDefinition)
  /// - `false` / unknown: return unchanged
  /// - `count`: handled at the handler level (bundle with total only)
  static Map<String, dynamic> shapeSummary(
    Map<String, dynamic> json,
    String mode,
  ) {
    switch (mode) {
      case 'text':
      case 'true':
        final shaped = <String, dynamic>{};
        for (final key in ['resourceType', 'id', 'meta', 'text']) {
          if (json.containsKey(key)) {
            shaped[key] = json[key];
          }
        }
        _addSubsettedTag(shaped);
        return shaped;

      case 'data':
        final shaped = Map<String, dynamic>.from(json);
        shaped.remove('text');
        _addSubsettedTag(shaped);
        return shaped;

      case 'false':
      default:
        return json;
    }
  }

  /// Shape a resource JSON to include only the specified elements
  /// plus the mandatory resourceType, id, and meta fields.
  static Map<String, dynamic> shapeElements(
    Map<String, dynamic> json,
    List<String> elements,
  ) {
    final allowedKeys = {'resourceType', 'id', 'meta', ...elements};
    final shaped = <String, dynamic>{};
    for (final key in json.keys) {
      if (allowedKeys.contains(key)) {
        shaped[key] = json[key];
      }
    }
    _addSubsettedTag(shaped);
    return shaped;
  }

  /// Add the SUBSETTED security tag to meta.
  static void _addSubsettedTag(Map<String, dynamic> json) {
    final meta = json['meta'] as Map<String, dynamic>? ?? {};
    final security =
        (meta['security'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    // Don't add if already present
    final alreadyPresent = security.any((t) => t['code'] == 'SUBSETTED');
    if (!alreadyPresent) {
      security.add(Map<String, dynamic>.from(_subsettedTag));
    }

    meta['security'] = security;
    json['meta'] = meta;
  }
}
