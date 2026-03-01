import 'package:fhirant_db/fhirant_db.dart';

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
  /// - 'includeIterate': List of _include:iterate parameters
  /// - 'revincludeIterate': List of _revinclude:iterate parameters
  /// - 'summary': String summary type or null
  /// - 'elements': List of element names or null
  /// - 'has': List of HasParameter for _has reverse chaining
  static Map<String, dynamic> parseQueryParameters(
    Map<String, String> queryParams,
  ) {
    final searchParams = <String, List<String>>{};
    int? count;
    int? offset;
    final sort = <String>[];
    final include = <String>[];
    final revinclude = <String>[];
    final includeIterate = <String>[];
    final revincludeIterate = <String>[];
    String? summary;
    List<String>? elements;
    final has = <HasParameter>[];

    // Special parameters that are not search parameters
    String? total;
    final unknownSpecialParams = <String>[];

    // All known _-prefixed parameters (special params + common search params)
    final specialParams = {
      '_count',
      '_offset',
      '_sort',
      '_include',
      '_revinclude',
      '_include:iterate',
      '_revinclude:iterate',
      '_summary',
      '_elements',
      '_total',
      '_format',
      '_pretty',
      '_contained',
      '_containedType',
      '_filter',
    };

    // Common _-prefixed search parameters that are valid across all resource types
    const knownUnderscoreSearchParams = {
      '_id',
      '_lastUpdated',
      '_tag',
      '_profile',
      '_security',
      '_source',
      '_text',
      '_content',
      '_list',
      '_type',
    };

    for (final entry in queryParams.entries) {
      final key = entry.key;
      final value = entry.value;

      // Detect _has: prefix before checking special params
      if (key.startsWith('_has:')) {
        final parsed = HasParameter.parse(key, value);
        if (parsed != null) {
          has.add(parsed);
        }
        continue;
      }

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
          case '_include:iterate':
            includeIterate.addAll(value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
            break;
          case '_revinclude:iterate':
            revincludeIterate.addAll(value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
            break;
          case '_summary':
            summary = value;
            break;
          case '_elements':
            // Elements is comma-separated
            elements = value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
            break;
          case '_total':
            // _total: none, accurate, estimate
            total = value;
            break;
        }
      } else {
        // Track unrecognized _-prefixed parameters for Prefer: handling=strict
        if (key.startsWith('_') && !knownUnderscoreSearchParams.contains(key)) {
          unknownSpecialParams.add(key);
        }

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
      'includeIterate': includeIterate.isEmpty ? null : includeIterate,
      'revincludeIterate': revincludeIterate.isEmpty ? null : revincludeIterate,
      'summary': summary,
      'elements': elements,
      'total': total,
      'unknownParams': unknownSpecialParams.isEmpty ? null : unknownSpecialParams,
      'has': has.isEmpty ? null : has,
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
      '_include:iterate',
      '_revinclude:iterate',
      '_summary',
      '_elements',
      '_total',
      '_format',
      '_pretty',
    };

    return queryParams.keys
        .any((key) => !specialParams.contains(key) || key.startsWith('_has:'));
  }
}
