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
  /// Parses a query string into search parameters.
  ///
  /// Takes the repetitions of each key, because R4 3.1.1.4.17 makes a repeated
  /// parameter an AND join — `?given=A&given=B` means BOTH — and
  /// `Uri.queryParameters` keeps only the LAST value for a repeated key, so
  /// reading it silently discarded every earlier one. `queryParametersAll` is
  /// what the caller must pass.
  static Map<String, dynamic> parseQueryParameters(
    Map<String, List<String>> queryParams,
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

    // Recognised so a lenient request is not rejected, but nothing acts on
    // them. R4 search.html distinguishes parameters a server does not
    // recognise from ones it "recognise[s] but do[es] not support", and asks
    // that both be reported when the client sends Prefer: handling=strict.
    // Answering 200 with the unfiltered set would tell a client that asked to
    // be warned that its filter had been applied.
    const unsupportedParams = {
      '_contained',
      '_containedType',
      '_filter',
    };

    // Common _-prefixed search parameters that are valid across all
    // resource types
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
      // Control parameters below take one value; only a search parameter
      // carries repetitions, and it keeps every one of them.
      for (final value in entry.value) {
        // Detect _has: prefix before checking special params
        if (key.startsWith('_has:')) {
          final parsed = HasParameter.parse(key, value);
          if (parsed != null) {
            has.add(parsed);
          }
          continue;
        }

        if (specialParams.contains(key)) {
          // Recognised but not acted on: report it alongside the unrecognised
          // ones so Prefer: handling=strict can refuse, while a lenient request
          // still ignores it as the spec asks.
          if (unsupportedParams.contains(key)) {
            unknownSpecialParams.add(key);
          }
          // Handle special parameters
          switch (key) {
            case '_count':
              count = int.tryParse(value);
            case '_offset':
              offset = int.tryParse(value);
            case '_sort':
              // Sort can be comma-separated: _sort=name,-date
              sort.addAll(
                value
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty),
              );
            case '_include':
              // Include can be repeated or comma-separated
              include.addAll(
                value
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty),
              );
            case '_revinclude':
              // Revinclude can be repeated or comma-separated
              revinclude.addAll(
                value
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty),
              );
            case '_include:iterate':
              includeIterate.addAll(
                value
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty),
              );
            case '_revinclude:iterate':
              revincludeIterate.addAll(
                value
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty),
              );
            case '_summary':
              summary = value;
            case '_elements':
              // Elements is comma-separated
              elements = value
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
            case '_total':
              // _total: none, accurate, estimate
              total = value;
          }
        } else {
          // Track unrecognized _-prefixed parameters, for
          // Prefer: handling=strict
          if (key.startsWith('_') &&
              !knownUnderscoreSearchParams.contains(key)) {
            unknownSpecialParams.add(key);
          }

          // A regular search parameter is passed on RAW, one entry per
          // repetition. The comma split and its escaping belong to the database
          // package, which is the only layer that can tell the two joins apart:
          // splitting here flattened `?given=A&given=B` (AND) and `?given=A,B`
          // (OR) into the same list, and they mean different things.
          (searchParams[key] ??= <String>[]).add(value);
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
      'unknownParams':
          unknownSpecialParams.isEmpty ? null : unknownSpecialParams,
      'has': has.isEmpty ? null : has,
    };
  }

  /// Check if there are any search parameters (excluding pagination)
  /// Whether any key is a real search parameter rather than a control one.
  ///
  /// Only the KEYS are inspected, so it accepts either shape: one value per
  /// key, or every repetition of it.
  static bool hasSearchParameters(Map<String, Object?> queryParams) {
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
