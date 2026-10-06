import 'dart:io';

import 'package:fhirant_server/src/utils/smart_scopes.dart';
import 'package:test/test.dart';

/// The per-route table of what each of the 89 routes asks a caller for
/// (REVIEW-2026-09-17 ST2b): the SMART permission `authorizeRequest`
/// derives from the method and path, the resource type it derives it on,
/// and the class of rule that applies before the scope check. The list is
/// written out so that a change to any derivation is a visible diff here,
/// and the route list itself is read from `createRouter`'s registrations,
/// as `every_route_is_guarded_test` reads it, so a new route with no row
/// fails this test.
///
/// Columns: verb, route, permission (c r u d s, `-` = no scope check at
/// this layer), resource type the permission is checked on (`-` = none),
/// class:
/// - `system`: admin role or a `system/` scope, before anything else
///   ($backup, $restore, $export at the root, $reindex, $reindex-status).
/// - `rootData`: a root operation that can read stored data the request
///   does not name ($fhirpath, $cql, the forecasts): a user- or
///   system-context scope covering every type.
/// - `owner`: the export status and file routes; authorized by the handler
///   against the job's owner.
/// - `-`: the ordinary scope check, or none.
///
/// What the table makes visible, each a deliberate reading and not a gap:
/// - `auth/*`, `/`, `/metadata`, `/favicon.ico`, `/.well-known/*` derive
///   nothing: they are public (auth_middleware `_publicPaths`), the token
///   is what they hand out. `GET /health` and `GET /ws` derive a search on
///   "health" / "ws" but are public too, so the derivation is never asked.
/// - `admin/*` derive `c`/`r`/`u` on the type "admin": the admin role's
///   `system/*.*` covers it and the handlers check the role themselves
///   (`_requireAdmin`); another role is refused by scope and by role alike.
/// - `POST /` (a Bundle) derives nothing here: the Bundle processor
///   authorizes every entry through the same `authorizeRequest`.
/// - `$validate` and `$transform` are NOT `rootData` although both resolve
///   conformance resources (StructureDefinition, ValueSet, ConceptMap,
///   StructureMap) from the store: the class is about data the request
///   does not name that a scope would confine, which conformance
///   resources are not.
/// - `GET /Patient/$export` and `GET /Group/<id>/$export` derive `r` on
///   Patient / Group; the kickoff handler then refuses a caller whose
///   scopes confine any exported type to a patient compartment, and the
///   system-level `GET /$export` needs system privilege.
/// - `GET /_history` and `POST /_search` derive `s` on `_history` /
///   `_search`, which `authorizeRequest` skips by name; the handlers check
///   each type they touch.
void main() {
  const table = <(String, String, String, String, String)>[
    ('GET', '/auth/status', '-', '-', '-'),
    ('POST', '/auth/register', '-', '-', '-'),
    ('POST', '/auth/login', '-', '-', '-'),
    ('POST', '/auth/token', '-', '-', '-'),
    ('POST', '/auth/revoke', '-', '-', '-'),
    ('POST', '/auth/logout', '-', '-', '-'),
    ('GET', '/auth/authorize', '-', '-', '-'),
    ('POST', '/auth/authorize', '-', '-', '-'),
    ('POST', '/auth/password', '-', '-', '-'),
    ('POST', '/admin/unlock/<userId>', 'c', 'admin', '-'),
    ('GET', '/admin/users', 'r', 'admin', '-'),
    ('POST', '/admin/users/<userId>/password', 'c', 'admin', '-'),
    ('POST', '/admin/users/<userId>/deactivate', 'c', 'admin', '-'),
    ('POST', '/admin/users/<userId>/activate', 'c', 'admin', '-'),
    ('PUT', '/admin/users/<userId>/role', 'u', 'admin', '-'),
    ('PUT', '/admin/users/<userId>/scopes', 'u', 'admin', '-'),
    ('GET', '/', '-', '-', '-'),
    ('GET', '/favicon.ico', '-', '-', '-'),
    ('GET', '/health', 's', 'health', '-'),
    ('GET', '/metadata', '-', '-', '-'),
    ('GET', '/.well-known/smart-configuration', '-', '-', '-'),
    ('POST', r'/Library/<id>/$evaluate', 'r', 'Library', '-'),
    ('POST', r'/Library/$evaluate', 'r', 'Library', '-'),
    ('ALL', r'/$validate', 'r', '-', '-'),
    ('ALL', r'/<resourceType>/$validate', 'r', 'Patient', '-'),
    ('GET', r'/CodeSystem/<id>/$validate-code', 'r', 'CodeSystem', '-'),
    ('POST', r'/CodeSystem/<id>/$validate-code', 'r', 'CodeSystem', '-'),
    ('GET', r'/CodeSystem/$validate-code', 'r', 'CodeSystem', '-'),
    ('POST', r'/CodeSystem/$validate-code', 'r', 'CodeSystem', '-'),
    ('GET', r'/ValueSet/<id>/$validate-code', 'r', 'ValueSet', '-'),
    ('POST', r'/ValueSet/<id>/$validate-code', 'r', 'ValueSet', '-'),
    ('GET', r'/ValueSet/$validate-code', 'r', 'ValueSet', '-'),
    ('POST', r'/ValueSet/$validate-code', 'r', 'ValueSet', '-'),
    ('GET', r'/CodeSystem/<id>/$lookup', 'r', 'CodeSystem', '-'),
    ('POST', r'/CodeSystem/<id>/$lookup', 'r', 'CodeSystem', '-'),
    ('GET', r'/CodeSystem/$lookup', 'r', 'CodeSystem', '-'),
    ('POST', r'/CodeSystem/$lookup', 'r', 'CodeSystem', '-'),
    ('GET', r'/ValueSet/<id>/$expand', 'r', 'ValueSet', '-'),
    ('POST', r'/ValueSet/<id>/$expand', 'r', 'ValueSet', '-'),
    ('GET', r'/ValueSet/$expand', 'r', 'ValueSet', '-'),
    ('POST', r'/ValueSet/$expand', 'r', 'ValueSet', '-'),
    ('GET', r'/NamingSystem/$preferred-id', 'r', 'NamingSystem', '-'),
    ('POST', r'/NamingSystem/$preferred-id', 'r', 'NamingSystem', '-'),
    ('GET', r'/ConceptMap/<id>/$translate', 'r', 'ConceptMap', '-'),
    ('POST', r'/ConceptMap/<id>/$translate', 'r', 'ConceptMap', '-'),
    ('GET', r'/ConceptMap/$translate', 'r', 'ConceptMap', '-'),
    ('POST', r'/ConceptMap/$translate', 'r', 'ConceptMap', '-'),
    ('GET', r'/CodeSystem/<id>/$subsumes', 'r', 'CodeSystem', '-'),
    ('POST', r'/CodeSystem/<id>/$subsumes', 'r', 'CodeSystem', '-'),
    ('GET', r'/CodeSystem/$subsumes', 'r', 'CodeSystem', '-'),
    ('POST', r'/CodeSystem/$subsumes', 'r', 'CodeSystem', '-'),
    ('POST', r'/$reindex', 'r', '-', 'system'),
    ('GET', r'/$reindex-status', 'r', '-', 'system'),
    ('POST', r'/$backup', 'r', '-', 'system'),
    ('POST', r'/$restore', 'r', '-', 'system'),
    ('GET', r'/$fhirpath', 'r', '-', 'rootData'),
    ('POST', r'/$fhirpath', 'r', '-', 'rootData'),
    ('POST', r'/$cql', 'r', '-', 'rootData'),
    ('POST', r'/$immds-forecast', 'r', '-', 'rootData'),
    ('POST', r'/$immds-forecast-who', 'r', '-', 'rootData'),
    ('GET', '/ws', 's', 'ws', '-'),
    ('POST', r'/$transform', 'r', '-', '-'),
    ('GET', r'/$export', 'r', '-', 'system'),
    ('GET', r'/Group/<groupId>/$export', 'r', 'Group', '-'),
    ('GET', r'/Patient/$export', 'r', 'Patient', '-'),
    ('GET', r'/$export-poll-status/<jobId>', 'r', '-', 'owner'),
    ('DELETE', r'/$export-poll-status/<jobId>', 'd', '-', 'owner'),
    ('GET', r'/$export-file/<jobId>/<fileName>', 'r', '-', 'owner'),
    ('GET', r'/Composition/<id>/$document', 'r', 'Composition', '-'),
    ('GET', r'/<compartmentType>/<id>/$everything', 'r', 'Patient', '-'),
    ('GET', r'/<resourceType>/<id>/$meta', 'r', 'Patient', '-'),
    ('POST', r'/<resourceType>/<id>/$meta-add', 'u', 'Patient', '-'),
    ('POST', r'/<resourceType>/<id>/$meta-delete', 'u', 'Patient', '-'),
    ('GET', '/<resourceType>/<id>/_history/<vid>', 'r', 'Patient', '-'),
    ('GET', '/<resourceType>/<id>/_history', 'r', 'Patient', '-'),
    ('GET', '/<resourceType>/_history', 'r', 'Patient', '-'),
    ('GET', '/_history', 's', '_history', '-'),
    (
      'GET',
      '/<compartmentType>/<compartmentId>/<resourceType>',
      'r',
      'Patient',
      '-'
    ),
    ('POST', '/_search', 's', '_search', '-'),
    ('POST', '/', '-', '-', '-'),
    ('GET', '/<resourceType>', 's', 'Patient', '-'),
    ('POST', '/<resourceType>/_search', 's', 'Patient', '-'),
    ('POST', '/<resourceType>', 'c', 'Patient', '-'),
    ('GET', '/<resourceType>/<id>', 'r', 'Patient', '-'),
    ('PUT', '/<resourceType>', 'u', 'Patient', '-'),
    ('PUT', '/<resourceType>/<id>', 'u', 'Patient', '-'),
    ('PATCH', '/<resourceType>/<id>', 'u', 'Patient', '-'),
    ('DELETE', '/<resourceType>/<id>', 'd', 'Patient', '-'),
    ('DELETE', '/<resourceType>', 'd', 'Patient', '-'),
  ];

  List<({String verb, String path})> registeredRoutes() {
    final source = File('lib/src/fhirant_server.dart').readAsStringSync();
    final pattern = RegExp(
      r"\.\.(get|post|put|delete|patch|all|head|mount|add)\(\s*r?'([^']+)'",
      dotAll: true,
    );
    return [
      for (final m in pattern.allMatches(source))
        (verb: m.group(1)!.toUpperCase(), path: m.group(2)!),
    ];
  }

  String concrete(String path) => path
      .replaceAll('<resourceType>', 'Patient')
      .replaceAll('<compartmentType>', 'Patient')
      .replaceAll('<compartmentId>', 'p1')
      .replaceAll('<groupId>', 'g1')
      .replaceAll('<userId>', '1')
      .replaceAll('<jobId>', 'j1')
      .replaceAll('<fileName>', 'f.ndjson')
      .replaceAll('<vid>', '1')
      .replaceAll('<id>', 'x1');

  String classOf(String path) {
    if (SmartScopeEnforcer.isPrivilegedSystemOperation(path)) return 'system';
    if (SmartScopeEnforcer.isOwnerCheckedOperation(path)) return 'owner';
    if (SmartScopeEnforcer.isRootDataOperation(path)) return 'rootData';
    return '-';
  }

  test('every registered route has exactly one row, and no row is stale', () {
    final routes = registeredRoutes().map((r) => '${r.verb} ${r.path}').toSet();
    final rows = table.map((r) => '${r.$1} ${r.$2}').toSet();
    expect(routes.difference(rows), isEmpty, reason: 'routes with no row');
    expect(rows.difference(routes), isEmpty, reason: 'rows with no route');
    expect(table, hasLength(89));
  });

  test('each row says what authorizeRequest derives for its route', () {
    final wrong = <String>[];
    for (final (verb, path, perm, type, kind) in table) {
      final c = concrete(path);
      final method = verb == 'ALL' ? 'POST' : verb;
      final got = (
        SmartScopeEnforcer.methodToPermission(method, c) ?? '-',
        SmartScopeEnforcer.resourceTypeFromPath(c) ?? '-',
        classOf(c),
      );
      if (got != (perm, type, kind)) {
        wrong.add('$verb $path: table ($perm, $type, $kind), derived $got');
      }
    }
    expect(wrong, isEmpty, reason: wrong.join('\n'));
  });

  test('an ALL route derives the same permission for GET and POST', () {
    // `$validate` is registered for every method; a GET and a POST of it
    // must ask the same thing, or the method would be a way round the rule.
    for (final (verb, path, perm, _, _) in table) {
      if (verb != 'ALL') continue;
      final c = concrete(path);
      expect(SmartScopeEnforcer.methodToPermission('GET', c), perm);
      expect(SmartScopeEnforcer.methodToPermission('POST', c), perm);
    }
  });
}
