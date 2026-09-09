import 'package:fhir_r4/fhir_r4.dart' as fhir;

/// Shapes a resource's JSON for `_summary` and `_elements`.
///
/// R4B search.html 3.1.1.5.8 and 3.1.1.5.9. Which elements are summary,
/// mandatory and modifier elements comes from `resourceElementSummary` in
/// fhir_r4, generated from every resource's StructureDefinition. This used to
/// be a hand-typed list for 24 resource types, with every other type's
/// `_summary=true` answered as `_summary=text`.
///
/// The cut is at the top level of the resource. 3.1.1.5.8 speaks of "all
/// supported elements that are marked as 'summary'", and the definitions mark
/// nested elements too (Attachment.data is not summary inside an element that
/// is); pruning inside a kept element is not done here. Documented deviation,
/// not an oversight.
class FhirResponseShaper {
  static const _subsettedTag = {
    'system': 'http://terminology.hl7.org/CodeSystem/v3-ObservationValue',
    'code': 'SUBSETTED',
    'display': 'subsetted',
  };

  /// Always kept: the resource's identity, and `meta`, which carries the
  /// SUBSETTED tag that says the rest was cut.
  static const _identity = {'resourceType', 'id', 'meta'};

  /// Shape a resource JSON according to the `_summary` mode.
  ///
  /// - `true`: "a limited subset of elements from the resource. This subset
  ///   SHOULD consist solely of all supported elements that are marked as
  ///   'summary' in the base definition of the resource(s)".
  /// - `text`: "Return only the "text" element, the 'id' element, the 'meta'
  ///   element, and only top-level mandatory elements".
  /// - `data`: "Remove the text element".
  /// - `false`: unchanged. `count` is the handler's (a bundle with a total).
  static Map<String, dynamic> shapeSummary(
    Map<String, dynamic> json,
    String mode,
  ) {
    final definition = _definitionOf(json);
    switch (mode) {
      case 'text':
        return _keep(json, {
          ..._identity,
          'text',
          ...?definition?.mandatory,
        });
      case 'true':
        // A type with no definition (not an R4 resource) keeps its identity
        // and text, which is the most that can be said of it.
        return _keep(json, {
          ..._identity,
          ...definition?.summary ?? {'text'},
        });
      case 'data':
        final shaped = Map<String, dynamic>.from(json)..remove('text');
        _addSubsettedTag(shaped);
        return shaped;
      case 'false':
      default:
        return json;
    }
  }

  /// Shape a resource JSON to the requested [elements].
  ///
  /// 3.1.1.5.9: "Only elements that are listed are to be returned ... Servers
  /// SHOULD always return mandatory elements whether they are requested or
  /// not." So the mandatory elements of the type come along, and so do
  /// `resourceType`, `id` and `meta`.
  static Map<String, dynamic> shapeElements(
    Map<String, dynamic> json,
    List<String> elements,
  ) {
    final definition = _definitionOf(json);
    return _keep(json, {
      ..._identity,
      ...elements,
      ...?definition?.mandatory,
    });
  }

  static fhir.ResourceElementSummary? _definitionOf(Map<String, dynamic> json) {
    final type = json['resourceType'];
    return type is String ? fhir.resourceElementSummary[type] : null;
  }

  /// [json] reduced to [names], each with its `_name` companion, tagged
  /// SUBSETTED. R4B json.html, "JSON representation of primitive elements":
  /// "If the value has an id attribute, or extensions, then this is
  /// represented as follows: ... a JSON property with `_` prepended to the
  /// name of the element, which, if present, contains the value's id and/or
  /// extensions".
  static Map<String, dynamic> _keep(
    Map<String, dynamic> json,
    Set<String> names,
  ) {
    final shaped = <String, dynamic>{};
    for (final key in json.keys) {
      final base = key.startsWith('_') ? key.substring(1) : key;
      if (names.contains(base)) {
        shaped[key] = json[key];
      }
    }
    _addSubsettedTag(shaped);
    return shaped;
  }

  /// Add the SUBSETTED tag to `meta.tag`.
  ///
  /// R4B search.html 3.1.1.5.8 (read 2026-09-08): "Servers SHOULD mark the
  /// resources with the tag SUBSETTED to ensure that the incomplete resource
  /// is not accidentally used to overwrite a complete resource." It is a
  /// tag; it used to be written to `meta.security`, where a client reading
  /// security labels would take it for one (REVIEW-2026-09-08 row 28).
  static void _addSubsettedTag(Map<String, dynamic> json) {
    final meta = Map<String, dynamic>.from(
      json['meta'] as Map<String, dynamic>? ?? {},
    );
    final tags = List<Map<String, dynamic>>.from(
      (meta['tag'] as List?)?.cast<Map<String, dynamic>>() ?? [],
    );

    // Don't add if already present
    final alreadyPresent = tags.any((t) => t['code'] == 'SUBSETTED');
    if (!alreadyPresent) {
      tags.add(Map<String, dynamic>.from(_subsettedTag));
    }

    meta['tag'] = tags;
    json['meta'] = meta;
  }
}
