import 'dart:convert';
import 'dart:typed_data';

import 'package:fhir_r4/fhir_r4.dart' as fhir;

/// One file a resource carries: where it sits, and its bytes; `null` bytes
/// when the value is not base64 at all, so cannot be read as a file.
///
/// [type] is the type the file declares, from its element's own field
/// ([typePath]): Binary.contentType, Attachment.contentType or
/// Signature.sigFormat. [typePath] is `null` where the element has no such
/// field (an extension's or a parameter's valueBase64Binary).
/// [typeRequired] says R4B requires it: Binary.contentType is 1..1, and
/// Attachment's att-1 reads "If the Attachment has data, it SHALL have a
/// contentType" (profiles-types.json and profiles-resources.json, read
/// 2026-10-21); Signature.sigFormat is 0..1.
///
/// [isFile] is false for the three base64Binary elements R4B defines as
/// something other than a file, whose bytes have no type to check:
/// Attachment.hash ("Hash of the data (sha-1, base64ed)"),
/// AuditEvent.entity.query ("Query parameters") and
/// Device.udiCarrier.carrierAIDC ("UDI Machine Readable Barcode String";
/// the short definitions, profiles-types.json and profiles-resources.json,
/// read 2026-10-21). Measured: Attachment.hash in the published
/// documentreference-example.json was refused as an unknown file before
/// these were set apart.
typedef FileData = ({
  String path,
  Uint8List? bytes,
  bool isFile,
  String? type,
  String? typePath,
  bool typeRequired,
});

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

Iterable<FileData> _walk(
  fhir.FhirBase node,
  String path, [
  _Declared? declared,
]) sync* {
  if (node is fhir.FhirBase64Binary) {
    final value = node.valueString;
    if (value != null) {
      yield (
        path: path,
        bytes: _decode(value),
        isFile: declared?.isFile ?? true,
        type: declared?.type,
        typePath: declared?.path,
        typeRequired: declared?.required ?? false,
      );
    }
  }
  final dataType = _declaredType(node, path);
  final notFile = _notAFile[node.fhirType];
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
      yield* _walk(
        children[i],
        '$path.$step$at',
        name == 'data'
            ? dataType
            : name == notFile
                ? _notAFileSlot
                : null,
      );
    }
  }
}

typedef _Declared = ({
  String? type,
  String? path,
  bool required,
  bool isFile,
});

/// The one base64Binary child of each of these that is not a file (see
/// [FileData]), by the type name fhir_r4 gives the element.
const _notAFile = {
  'Attachment': 'hash',
  'AuditEventEntity': 'query',
  'DeviceUdiCarrier': 'carrierAIDC',
};

const _Declared _notAFileSlot =
    (type: null, path: null, required: false, isFile: false);

/// The type [node] declares for its `data`, when it is one of the three
/// elements that carry a file beside its type.
_Declared? _declaredType(fhir.FhirBase node, String path) => switch (node) {
      fhir.Binary() => (
          type: node.contentType.valueString,
          path: '$path.contentType',
          required: true,
          isFile: true,
        ),
      fhir.Attachment() => (
          type: node.contentType?.valueString,
          path: '$path.contentType',
          required: true,
          isFile: true,
        ),
      fhir.Signature() => (
          type: node.sigFormat?.valueString,
          path: '$path.sigFormat',
          required: false,
          isFile: true,
        ),
      _ => null,
    };

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
