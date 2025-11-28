/// Utility for parsing FHIR search parameters from query strings
class SearchParameterParser {
  /// Parse query parameters into search parameters and pagination parameters
  /// 
  /// Returns a map with:
  /// - 'searchParams': Map of search parameter name to list of values
  /// - 'count': int or null
  /// - 'offset': int or null
  /// - 'sort': List of sort parameters (e.g., ['name', '-date'])
  /// - 'include': List of include parameters
  /// - 'revinclude': List of revinclude parameters
  /// - 'summary': String summary type or null
  /// - 'elements': List of element names or null
  static Map<String, dynamic> parseQueryParameters(
    Map<String, String> queryParams,
  ) {
    final searchParams = <String, List<String>>{};
    int? count;
    int? offset;
    final sort = <String>[];
    final include = <String>[];
    final revinclude = <String>[];
    String? summary;
    List<String>? elements;

    // Special parameters that are not search parameters
    final specialParams = {
      '_count',
      '_offset',
      '_sort',
      '_include',
      '_revinclude',
      '_summary',
      '_elements',
      '_format',
      '_pretty',
      '_contained',
      '_containedType',
      '_filter',
    };

    for (final entry in queryParams.entries) {
      final key = entry.key;
      final value = entry.value;

      if (specialParams.contains(key)) {
        // Handle special parameters
        switch (key) {
          case '_count':
            count = int.tryParse(value);
            break;
          case '_offset':
            offset = int.tryParse(value);
            break;
          case '_sort':
            // Sort can be comma-separated: _sort=name,-date
            sort.addAll(value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
            break;
          case '_include':
            // Include can be repeated or comma-separated
            include.addAll(value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
            break;
          case '_revinclude':
            // Revinclude can be repeated or comma-separated
            revinclude.addAll(value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
            break;
          case '_summary':
            summary = value;
            break;
          case '_elements':
            // Elements is comma-separated
            elements = value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
            break;
          // Other special params are not yet implemented but we capture them
        }
      } else {
        // Regular search parameter
        // Handle comma-separated values (OR logic)
        final values = value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        
        if (searchParams.containsKey(key)) {
          // Parameter already exists (can happen with repeated params)
          searchParams[key]!.addAll(values);
        } else {
          searchParams[key] = values;
        }
      }
    }

    return {
      'searchParams': searchParams.isEmpty ? null : searchParams,
      'count': count,
      'offset': offset,
      'sort': sort.isEmpty ? null : sort,
      'include': include.isEmpty ? null : include,
      'revinclude': revinclude.isEmpty ? null : revinclude,
      'summary': summary,
      'elements': elements,
    };
  }

  /// Check if there are any search parameters (excluding pagination)
  static bool hasSearchParameters(Map<String, String> queryParams) {
    final specialParams = {
      '_count',
      '_offset',
      '_sort',
      '_include',
      '_revinclude',
      '_summary',
      '_elements',
      '_format',
      '_pretty',
    };
    
    return queryParams.keys.any((key) => !specialParams.contains(key));
  }
}
