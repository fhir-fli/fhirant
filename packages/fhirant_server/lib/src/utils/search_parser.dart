import 'package:fhirant_db/fhirant_db.dart';

/// Utility for parsing FHIR search parameters from query strings
/// The most entries one page carries; a larger `_count` is clamped to it.
/// R4B search.html 3.1.1.5.3 "Page Count", read 2026-09-08: "Servers SHALL
/// NOT return more resources than requested, even if they don't support
/// paging, but may return less than the client requested. The server should
/// repeat the original _count parameter in its returned page links so that
/// subsequent paging requests honor the original _count." So the page is
/// smaller and the links carry the `_count` the client sent. Before this a
/// `_count=100000` hydrated every match into one bundle
/// (REVIEW-2026-09-06 finding 22).
const kMaxPageSize = 500;

/// Why `_count` or `_offset` cannot page a result, or null when they can:
/// each must be an integer of zero or more. Nothing negative pages anything,
/// and reading `_count=-1` as the default answered a malformed request as
/// though it were well formed.
String? pageArgumentError(String? count, String? offset) {
  if (count != null && (int.tryParse(count) ?? -1) < 0) {
    return '_count must be an integer of zero or more, not "$count"';
  }
  if (offset != null && (int.tryParse(offset) ?? -1) < 0) {
    return '_offset must be an integer of zero or more, not "$offset"';
  }
  return null;
}

/// [count], already checked by [pageArgumentError], as a page size:
/// [defaultCount] when absent, never above [kMaxPageSize].
int pageSize(String? count, {int defaultCount = 20}) =>
    (count == null ? defaultCount : int.parse(count)).clamp(0, kMaxPageSize);

class SearchParameterParser {
  /// Parse query parameters into search parameters and pagination parameters
  ///
  /// Returns a map with:
  /// - 'searchParams': Map of search parameter name to list of values
  /// - 'count': int or null, never above [kMaxPageSize]
  /// - 'invalidParams': a `List<String>` of why `_count`/`_offset` are
  ///   refused,
  ///   or null
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
    String? filter;
    String? contained;
    String? containedType;
    String? query;
    final unknownSpecialParams = <String>[];
    final invalidParams = <String>[];

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
      '_query',
    };

    // Recognised so a lenient request is not rejected, but nothing acts on
    // them. R4 search.html distinguishes parameters a server does not
    // recognise from ones it "recognise[s] but do[es] not support", and asks
    // that both be reported when the client sends Prefer: handling=strict.
    // Answering 200 with the unfiltered set would tell a client that asked to
    // be warned that its filter had been applied.
    // `_contained=false` is the spec's default and is what this server does,
    // so it is answered rather than reported. `true` and `both` ask for
    // resources inside other resources' `contained` element, which is neither
    // stored nor indexed here (measured 2026-09-02: saving an Observation with
    // a contained Patient stores the Observation only), so those are refused
    // in the handler, under any Prefer header.
    const unsupportedParams = <String>{};

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
              final error = pageArgumentError(value, null);
              if (error != null) {
                invalidParams.add(error);
              } else {
                count = pageSize(value);
              }
            case '_offset':
              final error = pageArgumentError(null, value);
              if (error != null) {
                invalidParams.add(error);
              } else {
                offset = int.parse(value);
              }
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
            case '_contained':
              contained = value;
            case '_containedType':
              containedType = value;
            case '_filter':
              // Carried whole. Its own grammar owns every character after
              // this point, so nothing here splits, trims or lower-cases it.
              filter = value;
            case '_query':
              // R4 3.1.1.7: "Servers processing search requests SHALL refuse
              // to process a search request if they do not recognize the
              // _query parameter value." Carried to the handler, which
              // defines no named queries and refuses every value. It used to
              // be an unknown parameter and ignored, so `_query=anything`
              // was answered with the unfiltered set.
              query = value;
          }
        } else {
          // Track unrecognized _-prefixed parameters, for
          // Prefer: handling=strict
          if (key.startsWith('_') &&
              !knownUnderscoreSearchParams.contains(key)) {
            unknownSpecialParams.add(key);
            // And do NOT pass it on as a search parameter. The `_` names are
            // the specification's own, so one this server does not know is not
            // a resource-specific parameter that might match something: it is
            // unrecognised, and R4 search.html says "servers SHOULD ignore
            // unknown or unsupported parameters". Passing it through made the
            // search look for a parameter that cannot exist and return
            // nothing, which is the opposite of ignoring it — a lenient
            // request got an empty bundle instead of the unfiltered set.
            continue;
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
      'filter': filter,
      'contained': contained,
      'containedType': containedType,
      'query': query,
      'unknownParams':
          unknownSpecialParams.isEmpty ? null : unknownSpecialParams,
      'invalidParams': invalidParams.isEmpty ? null : invalidParams,
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
