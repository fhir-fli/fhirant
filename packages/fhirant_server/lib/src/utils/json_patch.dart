import 'dart:convert';

/// Apply JSON Patch (RFC 6902) operations to a JSON document.
Map<String, dynamic> applyJsonPatch(
  Map<String, dynamic> document,
  List<dynamic> operations,
) {
  // Create a deep copy to avoid mutating the original
  final result = jsonDecode(jsonEncode(document)) as Map<String, dynamic>;

  for (final op in operations) {
    if (op is! Map<String, dynamic>) {
      throw FormatException('Invalid patch operation: must be an object');
    }

    final opType = op['op'] as String?;
    if (opType == null) {
      throw FormatException('Patch operation missing "op" field');
    }

    switch (opType) {
      case 'add':
        _applyAdd(result, op);
        break;
      case 'remove':
        _applyRemove(result, op);
        break;
      case 'replace':
        _applyReplace(result, op);
        break;
      case 'move':
        _applyMove(result, op);
        break;
      case 'copy':
        _applyCopy(result, op);
        break;
      case 'test':
        _applyTest(result, op);
        break;
      default:
        throw FormatException('Unknown patch operation: $opType');
    }
  }

  return result;
}

/// Convert FHIR Patch (Parameters resource) to JSON Patch format.
List<dynamic> convertFhirPatchToJsonPatch(Map<dynamic, dynamic> fhirPatch) {
  final operations = <Map<String, dynamic>>[];

  if (fhirPatch['parameter'] != null) {
    final parameters = fhirPatch['parameter'] as List;
    for (final param in parameters) {
      if (param is Map && param['name'] == 'operation') {
        final parts = param['part'] as List?;
        if (parts == null) continue;

        String? opType;
        String? path;
        dynamic value;

        for (final part in parts) {
          if (part is Map) {
            final name = part['name'] as String?;
            if (name == 'type') {
              opType = part['valueCode'] as String?;
            } else if (name == 'path') {
              path = part['valueString'] as String?;
            } else if (name == 'value') {
              value = _extractFhirValue(part as Map<String, dynamic>);
            }
          }
        }

        if (opType != null && path != null) {
          final jsonPath = _convertFhirPathToJsonPointer(path);

          final operation = <String, dynamic>{
            'op': _convertFhirOpToJsonOp(opType),
            'path': jsonPath,
          };

          if (value != null && opType != 'delete') {
            operation['value'] = value;
          }

          operations.add(operation);
        }
      }
    }
  }

  return operations;
}

/// Extract value from FHIR value* field.
dynamic _extractFhirValue(Map<String, dynamic> part) {
  for (final key in part.keys) {
    if (key.startsWith('value') && key != 'valueString') {
      return part[key];
    }
  }
  return part['valueString'];
}

/// Convert FHIR operation type to JSON Patch operation.
String _convertFhirOpToJsonOp(String fhirOp) {
  switch (fhirOp.toLowerCase()) {
    case 'add':
      return 'add';
    case 'insert':
      return 'add';
    case 'replace':
      return 'replace';
    case 'delete':
    case 'remove':
      return 'remove';
    case 'move':
      return 'move';
    default:
      return fhirOp.toLowerCase();
  }
}

/// Convert FHIR path to JSON Pointer.
String _convertFhirPathToJsonPointer(String fhirPath) {
  String path = fhirPath;
  if (path.contains('.')) {
    final parts = path.split('.');
    if (parts.length > 1) {
      path = parts.sublist(1).join('.');
    }
  }

  path = path.replaceAll('.', '/');

  if (!path.startsWith('/')) {
    path = '/$path';
  }

  return path;
}

void _applyAdd(Map<String, dynamic> document, Map<String, dynamic> op) {
  final path = op['path'] as String?;
  final value = op['value'];

  if (path == null) {
    throw FormatException('Add operation missing "path"');
  }

  final pointer = _parseJsonPointer(path);
  _setValueAtPath(document, pointer, value, add: true);
}

void _applyRemove(Map<String, dynamic> document, Map<String, dynamic> op) {
  final path = op['path'] as String?;

  if (path == null) {
    throw FormatException('Remove operation missing "path"');
  }

  final pointer = _parseJsonPointer(path);
  _removeValueAtPath(document, pointer);
}

void _applyReplace(Map<String, dynamic> document, Map<String, dynamic> op) {
  final path = op['path'] as String?;
  final value = op['value'];

  if (path == null) {
    throw FormatException('Replace operation missing "path"');
  }

  final pointer = _parseJsonPointer(path);
  _setValueAtPath(document, pointer, value, add: false);
}

void _applyMove(Map<String, dynamic> document, Map<String, dynamic> op) {
  final from = op['from'] as String?;
  final path = op['path'] as String?;

  if (from == null || path == null) {
    throw FormatException('Move operation missing "from" or "path"');
  }

  final fromPointer = _parseJsonPointer(from);
  final value = _getValueAtPath(document, fromPointer);
  if (value == null) {
    throw FormatException('Move operation: source path not found');
  }

  _removeValueAtPath(document, fromPointer);
  _setValueAtPath(document, _parseJsonPointer(path), value, add: true);
}

void _applyCopy(Map<String, dynamic> document, Map<String, dynamic> op) {
  final from = op['from'] as String?;
  final path = op['path'] as String?;

  if (from == null || path == null) {
    throw FormatException('Copy operation missing "from" or "path"');
  }

  final fromPointer = _parseJsonPointer(from);
  final value = _getValueAtPath(document, fromPointer);
  if (value == null) {
    throw FormatException('Copy operation: source path not found');
  }

  final copiedValue = jsonDecode(jsonEncode(value));
  _setValueAtPath(document, _parseJsonPointer(path), copiedValue, add: true);
}

void _applyTest(Map<String, dynamic> document, Map<String, dynamic> op) {
  final path = op['path'] as String?;
  final value = op['value'];

  if (path == null) {
    throw FormatException('Test operation missing "path"');
  }

  final pointer = _parseJsonPointer(path);
  final currentValue = _getValueAtPath(document, pointer);

  if (jsonEncode(currentValue) != jsonEncode(value)) {
    throw FormatException('Test operation failed: values do not match');
  }
}

List<String> _parseJsonPointer(String pointer) {
  if (!pointer.startsWith('/')) {
    throw FormatException('JSON Pointer must start with /');
  }

  if (pointer == '/') {
    return [];
  }

  return pointer
      .substring(1)
      .split('/')
      .map((segment) => segment.replaceAll('~1', '/').replaceAll('~0', '~'))
      .toList();
}

dynamic _getValueAtPath(
  Map<String, dynamic> document,
  List<String> path,
) {
  dynamic current = document;

  for (var i = 0; i < path.length; i++) {
    final segment = path[i];

    if (current is Map<String, dynamic>) {
      current = current[segment];
    } else if (current is List) {
      final index = int.tryParse(segment);
      if (index == null || index < 0 || index >= current.length) {
        return null;
      }
      current = current[index];
    } else {
      return null;
    }

    if (current == null) {
      return null;
    }
  }

  return current;
}

void _setValueAtPath(
  Map<String, dynamic> document,
  List<String> path,
  dynamic value, {
  required bool add,
}) {
  if (path.isEmpty) {
    throw FormatException('Cannot set root document');
  }

  dynamic current = document;

  for (var i = 0; i < path.length - 1; i++) {
    final segment = path[i];

    if (current is Map<String, dynamic>) {
      if (!current.containsKey(segment)) {
        if (add) {
          final nextSegment = path[i + 1];
          final nextIndex = int.tryParse(nextSegment);
          current[segment] = nextIndex != null ? [] : <String, dynamic>{};
        } else {
          throw FormatException(
              'Path not found: ${path.sublist(0, i + 1).join('/')}');
        }
      }
      current = current[segment];
    } else if (current is List) {
      final index = int.tryParse(segment);
      if (index == null || index < 0 || index >= current.length) {
        throw FormatException('Invalid array index: $segment');
      }
      current = current[index];
    } else {
      throw FormatException(
          'Path not found: ${path.sublist(0, i + 1).join('/')}');
    }
  }

  final lastSegment = path.last;
  final lastIndex = int.tryParse(lastSegment);

  if (current is Map<String, dynamic>) {
    if (lastIndex != null) {
      throw FormatException('Cannot use array index on object');
    }
    current[lastSegment] = value;
  } else if (current is List) {
    if (lastIndex == null) {
      throw FormatException('Array index required for list');
    }
    if (add && lastIndex == current.length) {
      current.add(value);
    } else if (lastIndex >= 0 && lastIndex < current.length) {
      current[lastIndex] = value;
    } else {
      throw FormatException('Array index out of bounds: $lastIndex');
    }
  } else {
    throw FormatException('Cannot set value at path: ${path.join('/')}');
  }
}

void _removeValueAtPath(Map<String, dynamic> document, List<String> path) {
  if (path.isEmpty) {
    throw FormatException('Cannot remove root document');
  }

  dynamic current = document;

  for (var i = 0; i < path.length - 1; i++) {
    final segment = path[i];

    if (current is Map<String, dynamic>) {
      if (!current.containsKey(segment)) {
        throw FormatException(
            'Path not found: ${path.sublist(0, i + 1).join('/')}');
      }
      current = current[segment];
    } else if (current is List) {
      final index = int.tryParse(segment);
      if (index == null || index < 0 || index >= current.length) {
        throw FormatException('Invalid array index: $segment');
      }
      current = current[index];
    } else {
      throw FormatException(
          'Path not found: ${path.sublist(0, i + 1).join('/')}');
    }
  }

  final lastSegment = path.last;
  final lastIndex = int.tryParse(lastSegment);

  if (current is Map<String, dynamic>) {
    if (lastIndex != null) {
      throw FormatException('Cannot use array index on object');
    }
    if (!current.containsKey(lastSegment)) {
      throw FormatException('Path not found: ${path.join('/')}');
    }
    current.remove(lastSegment);
  } else if (current is List) {
    if (lastIndex == null) {
      throw FormatException('Array index required for list');
    }
    if (lastIndex < 0 || lastIndex >= current.length) {
      throw FormatException('Array index out of bounds: $lastIndex');
    }
    current.removeAt(lastIndex);
  } else {
    throw FormatException('Cannot remove value at path: ${path.join('/')}');
  }
}
