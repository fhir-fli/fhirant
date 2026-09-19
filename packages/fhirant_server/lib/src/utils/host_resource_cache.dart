import 'dart:isolate';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhir_r4_path/fhir_r4_path.dart';
import 'package:fhirant_server/src/utils/program_sandbox.dart';

/// A [ResourceCache] for a program running in a worker isolate: every
/// lookup is asked of the host through [askHost] and answered by
/// [serveResourceCache] on the server's isolate, where the database is.
///
/// The mapping engine resolves canonicals while a transform runs (a
/// structure's StructureDefinition, a `translate` ConceptMap, an imported
/// StructureMap), so a sandboxed `$transform` (REVIEW-2026-09-17 A9) needs
/// the store reachable from the worker. Resources cross as JSON and are
/// memoised here by canonical URL, so each is fetched once per program.
class HostResourceCache extends ResourceCache {
  /// Creates a cache that asks [host].
  HostResourceCache(this.host);

  /// The port [serveResourceCache] listens on, through the sandbox.
  final SendPort host;

  final Map<String, fhir.CanonicalResource> _seen = {};

  @override
  Future<T?> getCanonicalResource<T extends fhir.CanonicalResource>(
    String url, [
    String? version,
  ]) async {
    final pipe = url.indexOf('|');
    final canonical = pipe < 0 ? url : url.substring(0, pipe);
    final wantVersion = version ?? (pipe < 0 ? null : url.substring(pipe + 1));
    final seen = _seen[canonical];
    if (seen is T &&
        (wantVersion == null || seen.version?.valueString == wantVersion)) {
      return seen;
    }
    final json = await askHost(
      host,
      (op: 'canonical', type: '$T', url: canonical, version: wantVersion),
    );
    if (json is! Map<String, dynamic>) return null;
    final resource = fhir.Resource.fromJson(json);
    if (resource is! T) return null;
    _seen[canonical] = resource;
    return resource;
  }

  @override
  Future<void> saveCanonicalResource(fhir.CanonicalResource resource) async {
    final url = resource.url?.valueString;
    if (url != null && url.isNotEmpty) {
      _seen[url] = resource;
    }
  }

  @override
  Future<Map<String, dynamic>?> getResourceMap(String url) async =>
      (await getCanonicalResource(url))?.toJson();

  @override
  Future<fhir.StructureDefinition?> getStructureDefinition(String url) =>
      getCanonicalResource<fhir.StructureDefinition>(url);

  @override
  Future<List<fhir.StructureDefinition>> getStructureDefinitions() async {
    final list = await askHost(
      host,
      (op: 'structureDefinitions', type: null, url: null, version: null),
    );
    return [
      for (final json in list! as List<Object?>)
        fhir.StructureDefinition.fromJson(json! as Map<String, dynamic>),
    ];
  }

  @override
  Future<fhir.CodeSystem?> getCodeSystem(String url, [String? version]) =>
      getCanonicalResource<fhir.CodeSystem>(url, version);

  @override
  Future<List<String>> getResourceNames() async {
    final list = await askHost(
      host,
      (op: 'resourceNames', type: null, url: null, version: null),
    );
    return (list! as List<Object?>).cast<String>();
  }
}

/// The request a [HostResourceCache] sends.
typedef ResourceCacheRequest = ({
  String op,
  String? type,
  String? url,
  String? version,
});

/// Answers a [HostResourceCache]'s request from [cache], on the server's
/// isolate. Pass as the `host` of `runHostedProgram`.
Future<Object?> serveResourceCache(ResourceCache cache, Object? request) async {
  final r = request! as ResourceCacheRequest;
  switch (r.op) {
    case 'canonical':
      final url = r.url!;
      final resource = switch (r.type) {
        'StructureDefinition' =>
          await cache.getCanonicalResource<fhir.StructureDefinition>(
            url,
            r.version,
          ),
        'ValueSet' =>
          await cache.getCanonicalResource<fhir.ValueSet>(url, r.version),
        'CodeSystem' =>
          await cache.getCanonicalResource<fhir.CodeSystem>(url, r.version),
        'ConceptMap' =>
          await cache.getCanonicalResource<fhir.ConceptMap>(url, r.version),
        'StructureMap' =>
          await cache.getCanonicalResource<fhir.StructureMap>(url, r.version),
        _ => await cache.getCanonicalResource<fhir.CanonicalResource>(
            url,
            r.version,
          ),
      };
      return resource?.toJson();
    case 'structureDefinitions':
      return [
        for (final sd in await cache.getStructureDefinitions()) sd.toJson(),
      ];
    case 'resourceNames':
      return cache.getResourceNames();
    default:
      throw ArgumentError('unknown resource cache request ${r.op}');
  }
}
