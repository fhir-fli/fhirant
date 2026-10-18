import 'package:fhir_r4/fhir_r4.dart' as fhir;

/// The coded elements of [resource] whose code the bound value set does not
/// define, as `path = code`, in document order.
///
/// The model gives a `code` element an enum class exactly where the
/// specification binds it `required` to a value set it defines, and a code
/// the class knows carries its CodeSystem (generator, REVIEW-2026-09-17
/// Q8). A code it does not know parses with no system. R4B http.html
/// 3.1.0.8 (read whole 2026-10-17): "When the resource syntax or data is
/// incorrect or invalid, and cannot be used to create a new resource, the
/// server returns a 400 Bad Request". `Observation.status:
/// "not-a-status"` used to be stored, read back and searched; the server's
/// own `$validate` of the stored copy rejected it (REVIEW-2026-10-17
/// finding 8).
List<String> unknownRequiredCodes(fhir.Resource resource) {
  final found = <String>[];
  void walk(fhir.FhirBase node, String path) {
    if (node is fhir.FhirCodeEnum) {
      final code = node.valueString;
      if (code != null && node.system == null) found.add('$path = $code');
      return;
    }
    for (final name in node.listChildrenNames()) {
      final children = node.getChildrenByName(name);
      for (var i = 0; i < children.length; i++) {
        walk(
          children[i],
          children.length > 1 ? '$path.$name[$i]' : '$path.$name',
        );
      }
    }
  }

  walk(resource, resource.resourceTypeString);
  return found;
}

/// The words a refusal of [codes] carries.
String unknownCodesMessage(List<String> codes) =>
    'Code(s) not in the required value set: ${codes.join('; ')}';
