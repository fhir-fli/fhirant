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
      throw const FormatException('Invalid patch operation: must be an object');
    }

    final opType = op['op'] as String?;
    if (opType == null) {
      throw const FormatException('Patch operation missing "op" field');
    }

    switch (opType) {
      case 'add':
        _applyAdd(result, op);
      case 'remove':
        _applyRemove(result, op);
      case 'replace':
        _applyReplace(result, op);
      case 'move':
        _applyMove(result, op);
      case 'copy':
        _applyCopy(result, op);
      case 'test':
        _applyTest(result, op);
      default:
        throw FormatException('Unknown patch operation: $opType');
    }
  }

  return result;
}

void _applyAdd(Map<String, dynamic> document, Map<String, dynamic> op) {
  final path = op['path'] as String?;
  final value = op['value'];

  if (path == null) {
    throw const FormatException('Add operation missing "path"');
  }

  final pointer = _parseJsonPointer(path);
  _setValueAtPath(document, pointer, value, add: true);
}

void _applyRemove(Map<String, dynamic> document, Map<String, dynamic> op) {
  final path = op['path'] as String?;

  if (path == null) {
    throw const FormatException('Remove operation missing "path"');
  }

  final pointer = _parseJsonPointer(path);
  _removeValueAtPath(document, pointer);
}

void _applyReplace(Map<String, dynamic> document, Map<String, dynamic> op) {
  final path = op['path'] as String?;
  final value = op['value'];

  if (path == null) {
    throw const FormatException('Replace operation missing "path"');
  }

  final pointer = _parseJsonPointer(path);
  _setValueAtPath(document, pointer, value, add: false);
}

void _applyMove(Map<String, dynamic> document, Map<String, dynamic> op) {
  final from = op['from'] as String?;
  final path = op['path'] as String?;

  if (from == null || path == null) {
    throw const FormatException('Move operation missing "from" or "path"');
  }

  final fromPointer = _parseJsonPointer(from);
  final value = _getValueAtPath(document, fromPointer);
  if (value == null) {
    throw const FormatException('Move operation: source path not found');
  }

  _removeValueAtPath(document, fromPointer);
  _setValueAtPath(document, _parseJsonPointer(path), value, add: true);
}

void _applyCopy(Map<String, dynamic> document, Map<String, dynamic> op) {
  final from = op['from'] as String?;
  final path = op['path'] as String?;

  if (from == null || path == null) {
    throw const FormatException('Copy operation missing "from" or "path"');
  }

  final fromPointer = _parseJsonPointer(from);
  final value = _getValueAtPath(document, fromPointer);
  if (value == null) {
    throw const FormatException('Copy operation: source path not found');
  }

  final copiedValue = jsonDecode(jsonEncode(value));
  _setValueAtPath(document, _parseJsonPointer(path), copiedValue, add: true);
}

void _applyTest(Map<String, dynamic> document, Map<String, dynamic> op) {
  final path = op['path'] as String?;
  final value = op['value'];

  if (path == null) {
    throw const FormatException('Test operation missing "path"');
  }

  final pointer = _parseJsonPointer(path);
  final currentValue = _getValueAtPath(document, pointer);

  if (jsonEncode(currentValue) != jsonEncode(value)) {
    throw const FormatException('Test operation failed: values do not match');
  }
}

List<String> _parseJsonPointer(String pointer) {
  if (!pointer.startsWith('/')) {
    throw const FormatException('JSON Pointer must start with /');
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
    throw const FormatException('Cannot set root document');
  }

  dynamic current = document;

  for (var i = 0; i < path.length - 1; i++) {
    final segment = path[i];

    if (current is Map<String, dynamic>) {
      if (!current.containsKey(segment)) {
        if (add) {
          final nextSegment = path[i + 1];
          final nextIndex = int.tryParse(nextSegment);
          current[segment] = nextIndex != null || nextSegment == '-'
              ? <dynamic>[]
              : <String, dynamic>{};
        } else {
          throw FormatException(
            'Path not found: ${path.sublist(0, i + 1).join('/')}',
          );
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
        'Path not found: ${path.sublist(0, i + 1).join('/')}',
      );
    }
  }

  final lastSegment = path.last;
  final lastIndex = int.tryParse(lastSegment);

  if (current is Map<String, dynamic>) {
    if (lastIndex != null) {
      throw const FormatException('Cannot use array index on object');
    }
    current[lastSegment] = value;
  } else if (current is List) {
    // RFC 6902 section 4.1, read 2026-09-08: for an array, "the supplied
    // value is added to the array at the indicated location. Any elements
    // at or above the specified index are shifted one position to the
    // right. The specified index MUST NOT be greater than the number of
    // elements in the array. If the "-" character is used to index the end
    // of the array (see [RFC6901]), this has the effect of appending the
    // value to the array." Before this, `-` was refused ("Array index
    // required for list") and an add at an existing index overwrote the
    // element instead of shifting it (REVIEW-2026-09-06 finding 21).
    if (add && lastSegment == '-') {
      current.add(value);
      return;
    }
    if (lastIndex == null) {
      throw const FormatException('Array index required for list');
    }
    if (add) {
      if (lastIndex < 0 || lastIndex > current.length) {
        throw FormatException('Array index out of bounds: $lastIndex');
      }
      current.insert(lastIndex, value);
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
    throw const FormatException('Cannot remove root document');
  }

  dynamic current = document;

  for (var i = 0; i < path.length - 1; i++) {
    final segment = path[i];

    if (current is Map<String, dynamic>) {
      if (!current.containsKey(segment)) {
        throw FormatException(
          'Path not found: ${path.sublist(0, i + 1).join('/')}',
        );
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
        'Path not found: ${path.sublist(0, i + 1).join('/')}',
      );
    }
  }

  final lastSegment = path.last;
  final lastIndex = int.tryParse(lastSegment);

  if (current is Map<String, dynamic>) {
    if (lastIndex != null) {
      throw const FormatException('Cannot use array index on object');
    }
    if (!current.containsKey(lastSegment)) {
      throw FormatException('Path not found: ${path.join('/')}');
    }
    current.remove(lastSegment);
  } else if (current is List) {
    if (lastIndex == null) {
      throw const FormatException('Array index required for list');
    }
    if (lastIndex < 0 || lastIndex >= current.length) {
      throw FormatException('Array index out of bounds: $lastIndex');
    }
    current.removeAt(lastIndex);
  } else {
    throw FormatException('Cannot remove value at path: ${path.join('/')}');
  }
}
