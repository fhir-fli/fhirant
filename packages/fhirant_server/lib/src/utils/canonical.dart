import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';

/// `url` and `version` of a canonical reference: `[url]` or `[url]|[version]`
/// (R4B references.html, read whole 2026-09-22, verbatim: "append the
/// version to the reference with a '|'").
({String url, String? version}) splitCanonical(String canonical) {
  final pipe = canonical.indexOf('|');
  return pipe < 0
      ? (url: canonical, version: null)
      : (
          url: canonical.substring(0, pipe),
          version: canonical.substring(pipe + 1)
        );
}

/// The one way an artefact is found by its canonical URL: the stored
/// resources of [type] whose `url` is the canonical's, narrowed to its
/// `|version` when it carries one. Before 2026-09-22 this search was
/// written at eight sites (five terminology, CQL, mapping, validation, and
/// the two resource caches), each splitting the version itself or not.
///
/// R4B references.html, verbatim: "Servers SHOULD support version specific
/// searching for canonical URLs by automatically detecting the presence of
/// a |[version] and performing the appropriate search". Which version is
/// chosen when none is asked and several are held is not decided here:
/// the store's order stands, and the page says the system "should pick the
/// latest version"; unmeasured whether the store's first hit is that.
Future<List<fhir.Resource>> findByCanonical(
  FhirAntDb db,
  fhir.R4ResourceType type,
  String canonical, {
  int? count,
}) {
  final (:url, :version) = splitCanonical(canonical);
  return db.search(
    resourceType: type,
    searchParameters: {
      'url': [url],
      if (version != null) 'version': [version],
    },
    count: count,
  );
}

/// The first [T] found by [findByCanonical], or null.
Future<T?> findOneByCanonical<T extends fhir.Resource>(
  FhirAntDb db,
  fhir.R4ResourceType type,
  String canonical,
) async {
  final hits = await findByCanonical(db, type, canonical, count: 1);
  for (final hit in hits) {
    if (hit is T) return hit;
  }
  return null;
}
