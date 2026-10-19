import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';

/// The query parameters a search actually used, and the links built from them.
///
/// R4 3.1.1.6: "In order to allow the client to be confident about what search
/// parameters were used as criteria by the server, the server SHALL return the
/// parameters that were actually used to process the search. Applications
/// processing search results SHALL check these returned values where
/// necessary. For example, if the server did not support some of the filters
/// specified in the search, the client would not want to display the results
/// as being appropriate to the specified filters. In the case of a RESTful
/// search, these parameters are encoded in the self link in the bundle that is
/// returned."
///
/// So the self link is not the request URL echoed back. A parameter the store
/// has no definition for was ignored (3.1.1.3), and echoing it would tell the
/// client its filter had run. The same used set builds the paging links, from
/// `queryParametersAll` rather than `queryParameters`: the latter keeps only
/// the LAST value of a repeated key, so the `next` page of `given=A&given=B`
/// used to run `given=B`.
/// The definition of a search parameter [code] on [resourceType], or null.
typedef ParameterLookup = SearchParameterDefinition? Function(
  String resourceType,
  String code,
);

/// The store's lookup: the specification's parameters, else the ones
/// uploaded as SearchParameters (`FhirDao.lookupDefinition`), the uploads
/// loaded first. The specification's table alone (`searchParameterFor`)
/// knew no upload, so a search by one was left out of the self link and
/// refused under `Prefer: handling=strict` though the store ran it (found
/// fixing REVIEW-2026-10-17's smaller list).
Future<ParameterLookup> storeLookup(FhirAntDb db) async {
  await db.customSearchParameters;
  return db.fhirDao.lookupDefinition;
}

class SearchLinks {
  SearchLinks._(this.used, this.ignored);

  /// Decides which of [query]'s parameters a search of [resourceType] uses,
  /// a parameter's definition read through [lookup].
  ///
  /// Control parameters (`_count`, `_summary`, ...) are kept as given. A
  /// `_has` is kept when it parses. A search parameter is kept when [lookup]
  /// has a definition for its name on this type (or on Resource /
  /// DomainResource, where `_id`, `_lastUpdated`, `_tag`, ... are published);
  /// the modifier or chain after the name is the store's to validate and is
  /// carried through. A `_sort` rule is kept when its parameter is defined.
  /// An `_include` or `_revinclude` value is kept when it can join
  /// ([_joins]). Everything else is [ignored].
  factory SearchLinks.decide(
    String resourceType,
    Map<String, List<String>> query,
    ParameterLookup lookup,
  ) {
    final used = <String, List<String>>{};
    final ignored = <String>[];
    for (final entry in query.entries) {
      final key = entry.key;
      if (key.startsWith('_has:')) {
        if (entry.value.any((v) => HasParameter.parse(key, v) != null)) {
          used[key] = entry.value;
        } else {
          ignored.add(key);
        }
        continue;
      }
      if (key == '_sort') {
        final rules = <String>[];
        for (final value in entry.value) {
          final kept = <String>[];
          for (final rule in value.split(',').map((s) => s.trim())) {
            if (rule.isEmpty) continue;
            final name = rule.startsWith('-') ? rule.substring(1) : rule;
            if (name == '_id' ||
                name == '_lastUpdated' ||
                lookup(resourceType, name) != null) {
              kept.add(rule);
            } else {
              ignored.add('_sort=$rule');
            }
          }
          if (kept.isNotEmpty) rules.add(kept.join(','));
        }
        if (rules.isNotEmpty) used[key] = rules;
        continue;
      }
      if (joinParameters.contains(key)) {
        final kept = <String>[];
        for (final value in entry.value) {
          final specs = [
            for (final spec in value.split(',').map((s) => s.trim()))
              if (spec.isNotEmpty) spec,
          ];
          for (final spec in specs) {
            if (!_joins(spec, lookup)) ignored.add('$key=$spec');
          }
          final joining = specs.where((spec) => _joins(spec, lookup));
          if (joining.isNotEmpty) kept.add(joining.join(','));
        }
        if (kept.isNotEmpty) used[key] = kept;
        continue;
      }
      if (controlParameters.contains(key)) {
        used[key] = entry.value;
        continue;
      }
      final name = SearchQueryKey.parse(key).name;
      if (lookup(resourceType, name) != null) {
        used[key] = entry.value;
      } else {
        ignored.add(key);
      }
    }
    return SearchLinks._(used, ignored);
  }

  /// The links of a history interaction: every parameter history takes
  /// (`_count`, `_offset`, `_since`, `_at`) is used, anything else ignored.
  /// http.html §3.1.0.14 (read 2026-09-08): "Servers SHOULD support paging
  /// for the results of a search or history interaction, and if they do,
  /// they SHALL conform to this method". History Bundles used to carry no
  /// links at all (REVIEW-2026-09-08 row 25).
  /// The parameters `$everything` takes (R4 operation
  /// patient-everything: `_since`, `_type`, `_count`; `_offset` and
  /// `_total` as this server pages). Anything else is [ignored].
  factory SearchLinks.everything(Map<String, List<String>> query) {
    const known = {'_count', '_offset', '_since', '_type', '_total', '_format'};
    final used = <String, List<String>>{};
    final ignored = <String>[];
    for (final entry in query.entries) {
      if (known.contains(entry.key)) {
        used[entry.key] = entry.value;
      } else {
        ignored.add(entry.key);
      }
    }
    return SearchLinks._(used, ignored);
  }

  factory SearchLinks.history(Map<String, List<String>> query) {
    const known = {'_count', '_offset', '_since', '_at', '_format', '_pretty'};
    final used = <String, List<String>>{};
    final ignored = <String>[];
    for (final entry in query.entries) {
      if (known.contains(entry.key)) {
        used[entry.key] = entry.value;
      } else {
        ignored.add(entry.key);
      }
    }
    return SearchLinks._(used, ignored);
  }

  /// [decide] with the store's own lookup: the specification's parameters
  /// and the ones uploaded as SearchParameters ([storeLookup]).
  static Future<SearchLinks> forStore(
    FhirAntDb db,
    String resourceType,
    Map<String, List<String>> query,
  ) async =>
      SearchLinks.decide(resourceType, query, await storeLookup(db));

  /// Whether [spec], an `_include` or `_revinclude` value, can join.
  ///
  /// R4B search.html 3.1.1.5.4 (read 2026-10-18, verbatim): "Parameter
  /// values for both _include and _revinclude have three parts, separated by
  /// a : character: The name of the source resource from which the join
  /// comes; The name of the search parameter which must be of type
  /// reference; (Optional) A specific of type of target resource". The
  /// second part may be `*`, "any search parameter of type=reference". A
  /// value that names no reference parameter of its source type joins
  /// nothing, so 3.1.1.6 keeps it out of the self link: it used to stay
  /// there (REVIEW-2026-10-17, smaller list).
  static bool _joins(String spec, ParameterLookup lookup) {
    final parts = spec.split(':');
    if (parts.length < 2 || parts.length > 3) return false;
    if (fhir.R4ResourceType.fromString(parts[0]) == null) return false;
    if (parts.length == 3 && fhir.R4ResourceType.fromString(parts[2]) == null) {
      return false;
    }
    return parts[1] == '*' || lookup(parts[0], parts[1])?.type == 'reference';
  }

  /// The `_include` or `_revinclude` values ([key]) the search used, one
  /// per join, for the code that runs them.
  List<String> joins(String key) => [
        for (final value in used[key] ?? const <String>[]) ...value.split(','),
      ];

  /// The joins: kept per value, by [_joins].
  static const joinParameters = <String>{
    '_include',
    '_revinclude',
    '_include:iterate',
    '_revinclude:iterate',
  };

  /// The links of one page: `self` and `first` always; `previous` when
  /// there is a page before; `next` while [offset] + [count] < [total];
  /// `last` when [total] is known and positive. A [count] of zero is a
  /// count-only page and carries `self` alone.
  /// The links of one page: `self` and `first` always; `previous` when
  /// there is a page before; `next` when [hasMore] (the caller's probe
  /// row, or `offset + count < total` when it has a total and no probe);
  /// `last` when the total is known and positive. [total] is null under
  /// `_total=none`, and paging goes on without it.
  List<fhir.BundleLink> page(
    Uri requested, {
    required int count,
    required int offset,
    required int? total,
    bool? hasMore,
  }) {
    fhir.BundleLink link(String relation, int at) => fhir.BundleLink(
          relation: fhir.FhirString(relation),
          url: fhir.FhirUri(url(requested, offset: at).toString()),
        );
    if (count <= 0) return [self(requested)];
    final more = hasMore ?? (total != null && offset + count < total);
    return [
      self(requested),
      link('first', 0),
      if (offset > 0) link('previous', (offset - count).clamp(0, offset)),
      if (more) link('next', offset + count),
      if (total != null && total > 0)
        link('last', ((total - 1) ~/ count) * count),
    ];
  }

  /// The result parameters of R4 3.1.1.1 and the ones this server adds
  /// (`_offset`, `_filter`). Not search parameters; kept as the client sent
  /// them.
  static const controlParameters = <String>{
    '_count',
    '_offset',
    '_sort',
    ...joinParameters,
    '_summary',
    '_elements',
    '_total',
    '_format',
    '_pretty',
    '_contained',
    '_containedType',
    '_filter',
    '_query',
    '_type',
  };

  /// The parameters the search used, one entry per repetition.
  final Map<String, List<String>> used;

  /// The keys the search ignored: no definition on this type, an unparseable
  /// `_has`, a `_sort` rule on an undefined parameter. What
  /// `Prefer: handling=strict` refuses.
  final List<String> ignored;

  /// [requested] with its query replaced by [used], `_offset` set to [offset]
  /// when given.
  Uri url(Uri requested, {int? offset}) {
    final params = <String, List<String>>{...used};
    if (offset != null) {
      params['_offset'] = ['$offset'];
    }
    if (params.isNotEmpty) return requested.replace(queryParameters: params);
    // Nothing was used. `replace(queryParameters: null)` would keep the
    // request's own query, and the self link would then name parameters the
    // search ignored (REVIEW-2026-10-17 finding 2), so the URL is rebuilt
    // without one.
    return Uri(
      scheme: requested.scheme,
      userInfo: requested.userInfo,
      host: requested.host,
      port: requested.hasPort ? requested.port : null,
      path: requested.path,
    );
  }

  /// The self link for [requested].
  fhir.BundleLink self(Uri requested) => fhir.BundleLink(
        relation: fhir.FhirString('self'),
        url: fhir.FhirUri(url(requested).toString()),
      );
}
