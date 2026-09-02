import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhir_r4_path/fhir_r4_path.dart';
import 'package:fhirant_db/fhirant_db.dart';

/// The canonical types the mapping engine asks this cache for. The engine
/// calls `fetchResource<StructureDefinition>` when resolving a type,
/// `fetchResource<ValueSet>` for a translate target and
/// `fetchResource<ConceptMap>` for `translate`; StructureMap is here because a
/// map may `import` another.
const _canonicalTypes = <fhir.R4ResourceType>[
  fhir.R4ResourceType.StructureDefinition,
  fhir.R4ResourceType.ValueSet,
  fhir.R4ResourceType.CodeSystem,
  fhir.R4ResourceType.ConceptMap,
  fhir.R4ResourceType.StructureMap,
];

/// A [ResourceCache] backed by this server's own database.
///
/// It replaces a version whose `getStructureDefinition`, `getCodeSystem`,
/// `getResourceMap`, `getResourceNames`, `getStructureDefinitions` and `client`
/// all threw `UnimplementedError`, which made any map needing type resolution
/// fail.
///
/// A FHIR server resolves a canonical from what it holds, so a
/// StructureDefinition, ValueSet, CodeSystem, ConceptMap or StructureMap POSTed
/// to this server is what `\$transform` resolves against. **Nothing here goes
/// to the network**: `client` stays null, because fhirant runs on a device that
/// may not have one, and a transform whose result depended on connectivity
/// would not be reproducible.
///
/// Resources the engine resolves mid-transform are memoised in `_seen` and take
/// precedence, matching `CanonicalResourceCache`.
class DbResourceCache extends ResourceCache {
  /// Creates a cache over [db].
  DbResourceCache(this.db);

  /// The server database canonicals are read from.
  final FhirAntDb db;

  final Map<String, fhir.CanonicalResource> _seen = {};

  @override
  Future<void> saveCanonicalResource(fhir.CanonicalResource resource) async {
    final url = resource.url?.valueString;
    if (url != null && url.isNotEmpty) {
      _seen[url] = resource;
    }
  }

  @override
  Future<T?> getCanonicalResource<T extends fhir.CanonicalResource>(
    String url, [
    String? version,
  ]) async {
    // A canonical may carry its version after a pipe, and callers pass it
    // that way rather than in the `version` argument: the validation engine
    // asks for `http://hl7.org/fhir/ValueSet/administrative-gender|4.3.0`.
    // Searching for that whole string as the url matches nothing, so every
    // versioned binding failed to resolve.
    final pipe = url.indexOf('|');
    final canonical = pipe < 0 ? url : url.substring(0, pipe);
    final wantVersion = version ?? (pipe < 0 ? null : url.substring(pipe + 1));

    final seen = _seen[canonical];
    final versionMatches =
        wantVersion == null || seen?.version?.valueString == wantVersion;
    if (seen is T && versionMatches) {
      return seen;
    }
    for (final type in _canonicalTypes) {
      final hits = await db.search(
        resourceType: type,
        searchParameters: {
          'url': [canonical],
          if (wantVersion != null) 'version': [wantVersion],
        },
      );
      for (final hit in hits) {
        if (hit is T) {
          await saveCanonicalResource(hit);
          return hit;
        }
      }
    }
    return null;
  }

  @override
  Future<fhir.StructureDefinition?> getStructureDefinition(String url) =>
      getCanonicalResource<fhir.StructureDefinition>(url);

  @override
  Future<List<fhir.StructureDefinition>> getStructureDefinitions() async {
    final stored = await db.getResourcesByType(
      fhir.R4ResourceType.StructureDefinition,
    );
    return <fhir.StructureDefinition>{
      ..._seen.values.whereType<fhir.StructureDefinition>(),
      ...stored.whereType<fhir.StructureDefinition>(),
    }.toList();
  }

  @override
  Future<fhir.CodeSystem?> getCodeSystem(String url, [String? version]) =>
      getCanonicalResource<fhir.CodeSystem>(url, version);

  @override
  Future<Map<String, dynamic>?> getResourceMap(String url) async =>
      (await getCanonicalResource(url))?.toJson();

  /// The `name` of every canonical this cache knows about.
  ///
  /// `WorkerContext.getResourceNames` unions this with the core resource type
  /// names from the generated hierarchy table, so returning only what is
  /// loaded is correct and matches `CanonicalResourceCache`.
  @override
  Future<List<String>> getResourceNames() async {
    final names = <String>{};
    for (final resource in [
      ..._seen.values,
      for (final type in _canonicalTypes) ...await db.getResourcesByType(type),
    ]) {
      final name = resource
          .getChildrenByName('name')
          .whereType<fhir.FhirString>()
          .map((e) => e.valueString)
          .whereType<String>()
          .firstOrNull;
      if (name != null && name.isNotEmpty) {
        names.add(name);
      }
    }
    return names.toList();
  }
}
