import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_server/src/utils/search_links.dart';

/// The one way a page of results becomes a searchset Bundle.
///
/// Before 2026-09-22 the type search, the system search, the compartment
/// search and $everything each assembled their own: the total decided four
/// ways, the links written three times, and $everything's self link echoed
/// the raw request (R4B search.html, read whole 2026-09-22, verbatim: "the
/// server SHALL return the parameters that were actually used to process
/// the search … encoded in the self link").
///
/// [matches] are this page's match entries; [extra] follows them (included
/// resources, an OperationOutcome about a truncated include). [total] is
/// null when the client asked `_total=none`. [hasMore] comes from the
/// caller's probe row, so `next` survives having no total.
fhir.Bundle searchsetPage({
  required Uri requested,
  required SearchLinks links,
  required List<fhir.Resource> matches,
  required int count,
  required int offset,
  required bool hasMore,
  required int? total,
  Iterable<fhir.BundleEntry> extra = const [],
}) {
  final base = baseUrlOf(requested);
  final entries = <fhir.BundleEntry>[
    for (final resource in matches) matchEntry(resource, base),
    ...extra,
  ];
  return fhir.Bundle(
    type: fhir.BundleType.searchset,
    total: total == null ? null : fhir.FhirUnsignedInt(total),
    entry: entries.isEmpty ? null : entries,
    link: links.page(
      requested,
      count: count,
      offset: offset,
      total: total,
      hasMore: hasMore,
    ),
  );
}

/// A searchset with the total and no entries: `_summary=count`, or
/// `_count=0` (R4B search.html 3.1.1.5.3 treats them alike).
fhir.Bundle countOnlyPage({
  required Uri requested,
  required SearchLinks links,
  required int total,
}) =>
    fhir.Bundle(
      type: fhir.BundleType.searchset,
      total: fhir.FhirUnsignedInt(total),
      link: [links.self(requested)],
    );

/// One match entry: the resource, its absolute address, `search.mode`
/// match.
fhir.BundleEntry matchEntry(fhir.Resource resource, String baseUrl) {
  final id = resource.id?.toString() ?? '';
  return fhir.BundleEntry(
    resource: resource,
    fullUrl: id.isNotEmpty
        ? fhir.FhirUri('$baseUrl/${resource.resourceTypeString}/$id')
        : null,
    search: const fhir.BundleSearch(mode: fhir.SearchEntryMode.match),
  );
}

/// `scheme://host[:port]` of [requested]: what a fullUrl is built on.
String baseUrlOf(Uri requested) => requested.hasPort
    ? '${requested.scheme}://${requested.host}:${requested.port}'
    : '${requested.scheme}://${requested.host}';
