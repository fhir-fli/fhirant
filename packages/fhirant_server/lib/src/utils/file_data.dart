import 'dart:convert';
import 'dart:typed_data';

import 'package:fhir_r4/fhir_r4.dart' as fhir;

/// One file a resource carries: where it sits, and its bytes; `null` bytes
/// when the value is not base64 at all, so cannot be read as a file.
typedef FileData = ({String path, Uint8List? bytes});

/// Every base64Binary value in [resource], wherever it sits.
///
/// A file reaches this server only this way: the server takes FHIR JSON and
/// nothing else, and R4B gives base64Binary to Binary.data, Attachment.data,
/// Signature.data and every `[x]` that allows it (18 elements in
/// profiles-types and profiles-resources, read 2026-10-21). The walk goes by
/// type through every child the model lists, so contained resources and
/// extensions are reached, and no list of element names has to be kept in
/// step with the specification.
///
/// A path names a choice element as FHIRPath does (`Extension.value`, not
/// `valueBase64Binary`): the model lists it as `valueX`, and no R4B element
/// name ends in a capital X except a choice (checked over the same 205
/// definitions).
Iterable<FileData> fileData(fhir.Resource resource) =>
    _walk(resource, resource.resourceTypeString);

Iterable<FileData> _walk(fhir.FhirBase node, String path) sync* {
  if (node is fhir.FhirBase64Binary) {
    final value = node.valueString;
    if (value != null) yield (path: path, bytes: _decode(value));
  }
  // fhir_r4 0.14.0's PrimitiveType answers getChildrenByName('extension')
  // but lists no children, so a primitive's own extensions (JSON
  // `_birthDate.extension`) are asked for by name. Measured: without this, a
  // valueBase64Binary there was not found.
  final names = node is fhir.PrimitiveType
      ? const ['extension']
      : node.listChildrenNames();
  for (final name in names) {
    final step = name.endsWith('X') ? name.substring(0, name.length - 1) : name;
    final children = node.getChildrenByName(name);
    for (var i = 0; i < children.length; i++) {
      // FHIRPath's indexer, when there is more than one to tell apart.
      final at = children.length > 1 ? '[$i]' : '';
      yield* _walk(children[i], '$path.$step$at');
    }
  }
}

/// R4B base64Binary's regex (profiles-types, read 2026-10-21) is
/// `(\s*([0-9a-zA-Z\+/=]){4}\s*)+`: whitespace may sit between the groups of
/// four, and the published binary-example.json has a space in it. Dart's
/// decoder refuses whitespace, and so does fhir_r4's `FhirBase64Binary.object`
/// (measured on that example), so it is taken out first.
Uint8List? _decode(String value) {
  try {
    return base64.decode(value.replaceAll(_whitespace, ''));
  } on FormatException {
    return null;
  }
}

final _whitespace = RegExp(r'\s');
