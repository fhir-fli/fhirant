import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/services/disk_space.dart';
import 'package:fhirant_server/src/services/storage_floor.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// A disk whose free space the test sets.
class FakeDisk implements DiskSpace {
  FakeDisk({required this.free, required this.total});

  int free;
  final int total;
  bool readable = true;

  @override
  DiskUsage? measure(String path) =>
      readable ? (free: free, total: total) : null;
}

const int _gib = 1024 * 1024 * 1024;

/// What each registered route writes, read from its handler, written out
/// here by hand so the classifier is checked against an independent list.
/// A route added to `createRouter` and not here fails the first test.
const _expected = <String, StorageNeed>{
  'GET /auth/status': StorageNeed.none,
  'POST /auth/register': StorageNeed.none,
  'POST /auth/login': StorageNeed.none,
  'POST /auth/token': StorageNeed.none,
  'POST /auth/revoke': StorageNeed.none,
  'POST /auth/logout': StorageNeed.none,
  'GET /auth/authorize': StorageNeed.none,
  'POST /auth/authorize': StorageNeed.none,
  'POST /auth/password': StorageNeed.none,
  'POST /admin/unlock/<userId>': StorageNeed.none,
  'GET /admin/users': StorageNeed.none,
  'POST /admin/users/<userId>/password': StorageNeed.none,
  'POST /admin/users/<userId>/deactivate': StorageNeed.none,
  'POST /admin/users/<userId>/activate': StorageNeed.none,
  'PUT /admin/users/<userId>/role': StorageNeed.none,
  'PUT /admin/users/<userId>/scopes': StorageNeed.none,
  'GET /': StorageNeed.none,
  'GET /favicon.ico': StorageNeed.none,
  'GET /health': StorageNeed.none,
  'GET /metadata': StorageNeed.none,
  'GET /.well-known/smart-configuration': StorageNeed.none,
  r'POST /Library/<id>/$evaluate': StorageNeed.none,
  r'POST /Library/$evaluate': StorageNeed.none,
  r'ALL /$validate': StorageNeed.none,
  r'ALL /<resourceType>/$validate': StorageNeed.none,
  r'GET /CodeSystem/<id>/$validate-code': StorageNeed.none,
  r'POST /CodeSystem/<id>/$validate-code': StorageNeed.none,
  r'GET /CodeSystem/$validate-code': StorageNeed.none,
  r'POST /CodeSystem/$validate-code': StorageNeed.none,
  r'GET /ValueSet/<id>/$validate-code': StorageNeed.none,
  r'POST /ValueSet/<id>/$validate-code': StorageNeed.none,
  r'GET /ValueSet/$validate-code': StorageNeed.none,
  r'POST /ValueSet/$validate-code': StorageNeed.none,
  r'GET /CodeSystem/<id>/$lookup': StorageNeed.none,
  r'POST /CodeSystem/<id>/$lookup': StorageNeed.none,
  r'GET /CodeSystem/$lookup': StorageNeed.none,
  r'POST /CodeSystem/$lookup': StorageNeed.none,
  r'GET /ValueSet/<id>/$expand': StorageNeed.none,
  r'POST /ValueSet/<id>/$expand': StorageNeed.none,
  r'GET /ValueSet/$expand': StorageNeed.none,
  r'POST /ValueSet/$expand': StorageNeed.none,
  r'GET /NamingSystem/$preferred-id': StorageNeed.none,
  r'POST /NamingSystem/$preferred-id': StorageNeed.none,
  r'GET /ConceptMap/<id>/$translate': StorageNeed.none,
  r'POST /ConceptMap/<id>/$translate': StorageNeed.none,
  r'GET /ConceptMap/$translate': StorageNeed.none,
  r'POST /ConceptMap/$translate': StorageNeed.none,
  r'GET /CodeSystem/<id>/$subsumes': StorageNeed.none,
  r'POST /CodeSystem/<id>/$subsumes': StorageNeed.none,
  r'GET /CodeSystem/$subsumes': StorageNeed.none,
  r'POST /CodeSystem/$subsumes': StorageNeed.none,
  r'POST /$reindex': StorageNeed.reindex,
  r'GET /$reindex-status': StorageNeed.none,
  r'POST /$backup': StorageNeed.backup,
  r'POST /$restore': StorageNeed.restore,
  r'GET /$fhirpath': StorageNeed.none,
  r'POST /$fhirpath': StorageNeed.none,
  r'POST /$cql': StorageNeed.none,
  r'POST /$immds-forecast': StorageNeed.none,
  r'POST /$immds-forecast-who': StorageNeed.none,
  'GET /ws': StorageNeed.none,
  r'POST /$transform': StorageNeed.none,
  r'GET /$export': StorageNeed.export,
  r'GET /Group/<groupId>/$export': StorageNeed.export,
  r'GET /Patient/$export': StorageNeed.export,
  r'GET /$export-poll-status/<jobId>': StorageNeed.none,
  r'DELETE /$export-poll-status/<jobId>': StorageNeed.none,
  r'GET /$export-file/<jobId>/<fileName>': StorageNeed.none,
  r'GET /Composition/<id>/$document': StorageNeed.none,
  r'GET /<compartmentType>/<id>/$everything': StorageNeed.none,
  r'GET /<resourceType>/<id>/$meta': StorageNeed.none,
  r'POST /<resourceType>/<id>/$meta-add': StorageNeed.record,
  r'POST /<resourceType>/<id>/$meta-delete': StorageNeed.record,
  'GET /<resourceType>/<id>/_history/<vid>': StorageNeed.none,
  'GET /<resourceType>/<id>/_history': StorageNeed.none,
  'GET /<resourceType>/_history': StorageNeed.none,
  'GET /_history': StorageNeed.none,
  'GET /<compartmentType>/<compartmentId>/<resourceType>': StorageNeed.none,
  'POST /_search': StorageNeed.none,
  'POST /': StorageNeed.record,
  'GET /<resourceType>': StorageNeed.none,
  'POST /<resourceType>/_search': StorageNeed.none,
  'POST /<resourceType>': StorageNeed.record,
  'GET /<resourceType>/<id>': StorageNeed.none,
  'PUT /<resourceType>': StorageNeed.record,
  'PUT /<resourceType>/<id>': StorageNeed.record,
  'PATCH /<resourceType>/<id>': StorageNeed.record,
  'DELETE /<resourceType>/<id>': StorageNeed.record,
  'DELETE /<resourceType>': StorageNeed.record,
};

void main() {
  /// The routes, read from `createRouter`'s own registrations, as
  /// every_route_is_guarded_test reads them.
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

  /// A concrete URL path, without the leading slash, for a route pattern.
  String concrete(String path) => path
      .replaceAll('<resourceType>', 'Patient')
      .replaceAll('<compartmentType>', 'Patient')
      .replaceAll('<compartmentId>', 'p1')
      .replaceAll('<groupId>', 'g1')
      .replaceAll('<userId>', '1')
      .replaceAll('<jobId>', 'j1')
      .replaceAll('<fileName>', 'f.ndjson')
      .replaceAll('<vid>', '1')
      .replaceAll('<id>', 'p1')
      .substring(1);

  group('what each route writes', () {
    test('every registered route is in the list, and nothing else is', () {
      final registered = {
        for (final r in registeredRoutes()) '${r.verb} ${r.path}',
      };
      // 89 registrations, counted from the source on 2026-11-02.
      expect(registered.length, 89);
      expect(
        registered.difference(_expected.keys.toSet()),
        isEmpty,
        reason: 'registered and not classified here',
      );
      expect(
        _expected.keys.toSet().difference(registered),
        isEmpty,
        reason: 'classified here and not registered',
      );
    });

    test('the classifier agrees with the list on every route', () {
      final wrong = <String>[];
      for (final MapEntry(key: route, value: need) in _expected.entries) {
        final [verb, path] = route.split(' ');
        // ALL answers every method; each must agree.
        final verbs = verb == 'ALL' ? ['GET', 'POST', 'PUT'] : [verb];
        for (final v in verbs) {
          final got = storageNeedOf(v, concrete(path));
          if (got != need) wrong.add('$v $path: $got, expected $need');
        }
      }
      expect(wrong, isEmpty);
    });

    test('a path no route serves: a write is a write, a read a read', () {
      expect(
        storageNeedOf('POST', r'nothing/here/$frobnicate'),
        StorageNeed.record,
      );
      expect(storageNeedOf('PUT', 'nothing'), StorageNeed.record);
      expect(storageNeedOf('GET', 'nothing/here'), StorageNeed.none);
    });
  });

  group('the floor', () {
    late FhirAntDb db;
    late FakeDisk disk;
    late StorageFloor floor;
    // 100 GiB: the phone's line is its 500 MiB cap.
    const total = 100 * _gib;
    final line = StorageFloor.lowLine(total);

    setUp(() async {
      final server = await createTestServer(devMode: true);
      db = server.db;
      await server.handler(
        testRequest(
          'POST',
          '/Patient',
          body: jsonEncode({'resourceType': 'Patient', 'id': 'p1'}),
          headers: {'content-type': 'application/fhir+json'},
        ),
      );
      disk = FakeDisk(free: total, total: total);
      floor = StorageFloor(db, '.', disk: disk);
    });

    tearDown(() async => db.close());

    test("the phone's line is 5% or 500 MiB, the smaller", () {
      expect(StorageFloor.lowLine(4 * _gib), 4 * _gib * 5 ~/ 100);
      expect(StorageFloor.lowLine(100 * _gib), 500 * 1024 * 1024);
    });

    test('the current resources are summed from the store', () async {
      final row =
          await db.customSelect('SELECT resource FROM resources').getSingle();
      final stored = utf8.encode(row.data['resource'] as String).length;
      expect(await floor.activeBytes(), stored);
      expect(stored, greaterThan(0));
    });

    test('a write that would cut into either amount is refused', () async {
      final active = await floor.activeBytes();
      disk.free = line + active + 10;
      expect(await floor.refusal(StorageNeed.record, 10), isNull);
      expect(await floor.refusal(StorageNeed.record, 11), isNotNull);
      disk.free = line + active - 1;
      expect(await floor.refusal(StorageNeed.record, 0), isNotNull);
    });

    test('an export may use the room kept for it', () async {
      final active = await floor.activeBytes();
      disk.free = line + active;
      expect(await floor.refusal(StorageNeed.record, 1), isNotNull);
      expect(await floor.refusal(StorageNeed.export, 0), isNull);
      disk.free = line + active - 1;
      expect(await floor.refusal(StorageNeed.export, 0), isNotNull);
    });

    test('a backup or reindex needs the database again above the line',
        () async {
      final page = (await db.customSelect('PRAGMA page_size').getSingle())
          .data
          .values
          .first as int;
      final pages = (await db.customSelect('PRAGMA page_count').getSingle())
          .data
          .values
          .first as int;
      final free = (await db.customSelect('PRAGMA freelist_count').getSingle())
          .data
          .values
          .first as int;
      final size = (pages - free) * page;
      disk.free = line + size;
      expect(await floor.refusal(StorageNeed.backup, 0), isNull);
      expect(await floor.refusal(StorageNeed.reindex, 0), isNull);
      disk.free = line + size - 1;
      expect(await floor.refusal(StorageNeed.backup, 0), isNotNull);
      expect(await floor.refusal(StorageNeed.reindex, 0), isNotNull);
    });

    test('a restore needs twice its upload above the line', () async {
      disk.free = line + 2000;
      expect(await floor.refusal(StorageNeed.restore, 1000), isNull);
      expect(await floor.refusal(StorageNeed.restore, 1001), isNotNull);
    });

    test('nothing is refused for what needs no disk, however full', () async {
      disk.free = 0;
      expect(await floor.refusal(StorageNeed.none, 1 << 20), isNull);
    });

    test('a disk that cannot be read refuses nothing', () async {
      disk
        ..free = 0
        ..readable = false;
      expect(await floor.refusal(StorageNeed.record, 1), isNull);
    });

    test('an accepted write is counted until the next sum', () async {
      final before = await floor.activeBytes();
      floor.wrote(500);
      expect(await floor.activeBytes(), before + 500);
      await floor.refresh();
      expect(await floor.activeBytes(), before);
    });
  });

  group('through the server', () {
    const total = 100 * _gib;
    final line = StorageFloor.lowLine(total);

    // An update that creates: the id is the client's, so it can be read.
    Request create(String id, {String? token}) => testRequest(
          'PUT',
          '/Patient/$id',
          body: jsonEncode({'resourceType': 'Patient', 'id': id}),
          headers: {'content-type': 'application/fhir+json'},
          authToken: token,
        );

    test('a full disk refuses a create with 507 no-store, and reads go on',
        () async {
      final disk = FakeDisk(free: total, total: total);
      final server = await createTestServer(devMode: true, diskSpace: disk);
      addTearDown(server.db.close);
      expect((await server.handler(create('a'))).statusCode, 201);

      disk.free = line;
      final refused = await server.handler(create('b'));
      expect(refused.statusCode, 507);
      expect(
        refused.headers['content-type'],
        contains('application/fhir+json'),
      );
      final outcome =
          jsonDecode(await refused.readAsString()) as Map<String, dynamic>;
      final issue = (outcome['issue'] as List).single as Map<String, dynamic>;
      expect(issue['code'], 'no-store');
      expect(issue['diagnostics'], contains('MiB'));
      expect(
        await server.db.getResource(fhir.R4ResourceType.Patient, 'b'),
        isNull,
        reason: 'nothing was written',
      );

      expect(
        (await server.handler(testRequest('GET', '/Patient/a'))).statusCode,
        200,
      );
      expect(
        (await server.handler(testRequest('DELETE', '/Patient/a'))).statusCode,
        507,
      );

      disk.free = total;
      expect((await server.handler(create('b'))).statusCode, 201);
    });

    test('a caller with no credential is told nothing about the disk',
        () async {
      final disk = FakeDisk(free: 0, total: total);
      final server = await createTestServer(diskSpace: disk);
      addTearDown(server.db.close);
      expect((await server.handler(create('a'))).statusCode, 401);
    });

    test('an accepted create counts toward the room kept for an export',
        () async {
      final disk = FakeDisk(free: total, total: total);
      final server = await createTestServer(devMode: true, diskSpace: disk);
      addTearDown(server.db.close);
      final floor = server.server.storageFloor!;
      final before = await floor.activeBytes();
      final request = create('counted');
      final length = request.contentLength!;
      expect((await server.handler(request)).statusCode, 201);
      expect(await floor.activeBytes(), before + length);
    });
  });

  test('statvfs reads the same size df reports, on this machine', () async {
    if (!Platform.isLinux) return markTestSkipped('statvfs is read on Linux');
    final usage = StatvfsDiskSpace().measure('.');
    expect(usage, isNotNull);
    final df = await Process.run('df', ['-B1', '--output=size,avail', '.']);
    final [size, avail] = (df.stdout as String)
        .trim()
        .split('\n')
        .last
        .trim()
        .split(RegExp(r'\s+'))
        .map(int.parse)
        .toList();
    expect(usage!.total, size);
    // Free space moves while other things write; within 1 GiB.
    expect((usage.free - avail).abs(), lessThan(_gib));
  });
}
