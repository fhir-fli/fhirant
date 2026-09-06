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
class SearchLinks {
  SearchLinks._(this.used, this.ignored);

  /// Decides which of [query]'s parameters a search of [resourceType] uses.
  ///
  /// Control parameters (`_count`, `_sort`, `_include`, ...) are kept as
  /// given. A `_has` is kept when it parses. A search parameter is kept when
  /// the store has a definition for its name on this type (or on Resource /
  /// DomainResource, where `_id`, `_lastUpdated`, `_tag`, ... are published);
  /// the modifier or chain after the name is the store's to validate and is
  /// carried through. A `_sort` rule is kept when its parameter is defined.
  /// Everything else is [ignored].
  factory SearchLinks.decide(
    String resourceType,
    Map<String, List<String>> query,
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
                searchParameterFor(resourceType, name) != null) {
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
      if (controlParameters.contains(key)) {
        used[key] = entry.value;
        continue;
      }
      final name = SearchQueryKey.parse(key).name;
      if (searchParameterFor(resourceType, name) != null) {
        used[key] = entry.value;
      } else {
        ignored.add(key);
      }
    }
    return SearchLinks._(used, ignored);
  }

  /// The result parameters of R4 3.1.1.1 and the ones this server adds
  /// (`_offset`, `_filter`). Not search parameters; kept as the client sent
  /// them.
  static const controlParameters = <String>{
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
    return requested.replace(
      queryParameters: params.isEmpty ? null : params,
    );
  }

  /// The self link for [requested].
  fhir.BundleLink self(Uri requested) => fhir.BundleLink(
        relation: fhir.FhirString('self'),
        url: fhir.FhirUri(url(requested).toString()),
      );
}
