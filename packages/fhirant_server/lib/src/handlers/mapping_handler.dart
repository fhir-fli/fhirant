import 'dart:convert';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhir_r4_mapping/fhir_r4_mapping.dart';
import 'package:fhir_r4_path/fhir_r4_path.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:shelf/shelf.dart';

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
    final seen = _seen[url];
    final versionMatches =
        version == null || seen?.version?.valueString == version;
    if (seen is T && versionMatches) {
      return seen;
    }
    for (final type in _canonicalTypes) {
      final hits = await db.search(
        resourceType: type,
        searchParameters: {
          'url': [url],
          if (version != null) 'version': [version],
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

/// FHIR Mapping Handler - Transform resources using StructureMap
Future<Response> mappingHandler(Request request, FhirAntDb db) async {
  try {
    FhirantLogging().logInfo('Received mapping/transform request');

    final body = await request.readAsString();
    if (body.isEmpty) {
      return Response(
        400,
        body: jsonEncode({
          'resourceType': 'OperationOutcome',
          'issue': [
            {
              'severity': 'error',
              'code': 'invalid',
              'diagnostics': 'Request body is empty',
            }
          ],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    Map<String, dynamic> requestJson;
    try {
      requestJson = jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      return Response(
        400,
        body: jsonEncode({
          'resourceType': 'OperationOutcome',
          'issue': [
            {
              'severity': 'error',
              'code': 'invalid',
              'diagnostics': 'Invalid JSON format: $e',
            }
          ],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    if (requestJson['map'] == null) {
      return Response(
        400,
        body: jsonEncode({
          'resourceType': 'OperationOutcome',
          'issue': [
            {
              'severity': 'error',
              'code': 'invalid',
              'diagnostics': 'Missing required field: map (StructureMap)',
            }
          ],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    if (requestJson['source'] == null) {
      return Response(
        400,
        body: jsonEncode({
          'resourceType': 'OperationOutcome',
          'issue': [
            {
              'severity': 'error',
              'code': 'invalid',
              'diagnostics': 'Missing required field: source (source resource)',
            }
          ],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Parse StructureMap
    fhir.StructureMap structureMap;
    try {
      structureMap = fhir.StructureMap.fromJson(
        requestJson['map'] as Map<String, dynamic>,
      );
    } catch (e) {
      return Response(
        400,
        body: jsonEncode({
          'resourceType': 'OperationOutcome',
          'issue': [
            {
              'severity': 'error',
              'code': 'invalid',
              'diagnostics': 'Invalid StructureMap: $e',
            }
          ],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Parse source resource
    fhir.Resource source;
    try {
      final sourceData = requestJson['source'];
      final sourceString =
          sourceData is String ? sourceData : jsonEncode(sourceData);
      source = fhir.Resource.fromJsonString(sourceString);
    } catch (e) {
      return Response(
        400,
        body: jsonEncode({
          'resourceType': 'OperationOutcome',
          'issue': [
            {
              'severity': 'error',
              'code': 'invalid',
              'diagnostics': 'Invalid source resource: $e',
            }
          ],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // The engine cannot invent the target: given null it fails with
    // "Unable to create target of type <alias>". StructureMap-transform names
    // the target in the map itself, so build an empty instance of it here.
    final cache = DbResourceCache(db);
    final targetType = await _targetResourceType(structureMap, cache);
    if (targetType == null) {
      return Response(
        400,
        body: jsonEncode({
          'resourceType': 'OperationOutcome',
          'issue': [
            {
              'severity': 'error',
              'code': 'invalid',
              'diagnostics': 'StructureMap has no structure with mode "target"',
            }
          ],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    ResourceBuilder targetBuilder;
    try {
      targetBuilder = resourceFromJson(<String, dynamic>{
        'resourceType': targetType,
      });
    } catch (e) {
      return Response(
        400,
        body: jsonEncode({
          'resourceType': 'OperationOutcome',
          'issue': [
            {
              'severity': 'error',
              'code': 'not-supported',
              'diagnostics':
                  'Unsupported target type "$targetType". The target '
                      'structure canonical must name a base FHIR resource; '
                      'this server does not resolve a profile or logical '
                      'model canonical to its underlying type.',
            }
          ],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Convert Resource to builder for mapping engine
    // Resources have a toBuilder() method that returns FhirBaseBuilder
    final sourceBuilder = source.toBuilder;

    // Execute mapping
    final transformed = await fhirMappingEngine(
      sourceBuilder,
      structureMap,
      cache,
      targetBuilder,
    );

    if (transformed == null) {
      return Response(
        500,
        body: jsonEncode({
          'resourceType': 'OperationOutcome',
          'issue': [
            {
              'severity': 'error',
              'code': 'exception',
              'diagnostics': 'Mapping returned null result',
            }
          ],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // The engine reports a failed transform by RETURNING an OperationOutcome,
    // not by throwing: transformBuilder catches and calls _createOutcome. A map
    // that leaves a required element unset — Observation.status, Basic.code —
    // fails when the builder is built, and arrives here. Returning that as 200
    // tells the client the transform succeeded and hands it a resource of the
    // wrong type.
    final resultJson = transformed.toJson();
    if (resultJson['resourceType'] == 'OperationOutcome' &&
        targetType != 'OperationOutcome') {
      FhirantLogging().logError(
        'Mapping/transformation failed: the engine returned an '
        'OperationOutcome instead of a $targetType',
      );
      return Response(
        422,
        body: jsonEncode(resultJson),
        headers: {'Content-Type': 'application/json'},
      );
    }

    FhirantLogging().logInfo(
      'Resource transformation completed successfully',
    );

    return Response.ok(
      jsonEncode(resultJson),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('Mapping/transformation failed', e, stackTrace);
    return Response(
      500,
      body: jsonEncode({
        'resourceType': 'OperationOutcome',
        'issue': [
          {
            'severity': 'error',
            'code': 'exception',
            'diagnostics': 'Mapping error',
          }
        ],
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

/// The resource type a [StructureMap] produces.
///
/// Taken from the FIRST `structure` entry with `mode = target`, whose `url` is
/// typed `canonical(StructureDefinition)` by R4 structuremap.html. That page
/// gives **no rule** for turning the canonical into a type at execution; it
/// says only that "the StructureMap resource assumes that both the source and
/// the target models are fully defined using StructureDefinition resources -
/// either resources, or logical models". So this resolves the definition and
/// reads `StructureDefinition.type`, which structuredefinition.html makes
/// `1..1` and defines as "the type this structure describes". Checked against
/// the published definitions on disk rather than assumed: base `Patient` has
/// `type: "Patient"`, and the profile `us-core-patient` also has
/// `type: "Patient"` — which is what makes a profiled target resolve.
///
/// 🛑 The fallback IS a deviation and is labelled as one. When the canonical is
/// not in the cache or the database, this reads the last path segment of the
/// URL. That is right for a base FHIR canonical and wrong for an unknown
/// profile, so the caller gets a 400 naming what it could not resolve rather
/// than a guessed type. The cure is to POST the StructureDefinition to the
/// server first, which is what makes the map's structures "known to the
/// server".
///
/// `structure` is `0..*`. A map naming several targets uses the first; no spec
/// rule was found either way, and it is recorded in PLAN.md rather than
/// presented as correct.
Future<String?> _targetResourceType(
  fhir.StructureMap map,
  ResourceCache cache,
) async {
  for (final structure in map.structure ?? <fhir.StructureMapStructure>[]) {
    if (structure.mode.valueString != 'target') {
      continue;
    }
    final url = structure.url.valueString;
    if (url == null || url.isEmpty) {
      continue;
    }
    final resolved = await cache.getStructureDefinition(url);
    final declared = resolved?.type.valueString;
    if (declared != null && declared.isNotEmpty) {
      return declared;
    }
    final lastSegment = url.split('/').last;
    if (lastSegment.isNotEmpty) {
      return lastSegment;
    }
  }
  return null;
}
