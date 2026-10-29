import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// A transaction's plain creates are saved together (`_HeldCreates`,
/// bundle_handler.dart): a 2,000-entry Bundle made about 10,000 trips to
/// the store, five per entry (`tool/review_2026-10-17/
/// bundle_statements_probe.tsv`). Holding them must not change what the
/// transaction does. R4B http.html 3.1.0.11.2 (read whole 2026-10-17)
/// processes DELETE, then POST, then PUT/PATCH, then GET, in one
/// transaction; every read in it (a conditional create's search, a
/// conditional reference, a GET) still sees the writes before it.
class _Count extends QueryInterceptor {
  int statements = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements++;
    return executor.runSelect(statement, args);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements++;
    return executor.runInsert(statement, args);
  }

  @override
  Future<void> runBatched(QueryExecutor executor, BatchedStatements stmts) {
    statements++;
    return executor.runBatched(stmts);
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements++;
    return executor.runCustom(statement, args);
  }
}

void main() {
  late FhirAntDb db;
  late Handler handler;
  late String admin;
  late _Count count;

  setUp(() async {
    count = _Count();
    db = FhirAntDb(NativeDatabase.memory().interceptWith(count));
    await db.initialize();
    final server = FhirAntServer(db, jwtSecret: testJwtSecret);
    handler = server.createHandler(server.createRouter());
    admin = await issueTestToken(db, username: 'adm', scopes: ['system/*.*']);
  });

  tearDown(() => db.close());

  Future<Response> transaction(List<Map<String, dynamic>> entries) async =>
      handler(
        testRequest(
          'POST',
          '/',
          body: jsonEncode({
            'resourceType': 'Bundle',
            'type': 'transaction',
            'entry': entries,
          }),
          authToken: admin,
        ),
      );

  Map<String, dynamic> post(
    Map<String, dynamic> resource, {
    String? fullUrl,
    String? ifNoneExist,
  }) =>
      {
        if (fullUrl != null) 'fullUrl': fullUrl,
        'resource': resource,
        'request': {
          'method': 'POST',
          'url': resource['resourceType'],
          if (ifNoneExist != null) 'ifNoneExist': ifNoneExist,
        },
      };

  Map<String, dynamic> patient(String mrn) => {
        'resourceType': 'Patient',
        'identifier': [
          {'system': 'urn:mrn', 'value': mrn},
        ],
      };

  Map<String, dynamic> observation(String subject) => {
        'resourceType': 'Observation',
        'status': 'final',
        'code': {'text': 'potassium'},
        'subject': {'reference': subject},
      };

  Future<List<Map<String, dynamic>>> entriesOf(Response r) async {
    final body = await r.readAsString();
    expect(r.statusCode, 200, reason: body);
    return [
      for (final e in (jsonDecode(body) as Map)['entry'] as List)
        e as Map<String, dynamic>,
    ];
  }

  test('fifty plain creates take a handful of statements, not five each',
      () async {
    final before = count.statements;
    final entries = await entriesOf(
      await transaction([
        for (var i = 0; i < 50; i++) post(observation('Patient/p$i')),
      ]),
    );
    final used = count.statements - before;
    expect(entries, hasLength(50));
    // One at a time this was about 250 (5 x 50); what remains is the
    // request's own reads and one list save.
    expect(used, lessThan(50), reason: '$used statements');
  });

  test('creates past the hold limit are saved in chunks, every one stored',
      () async {
    // 250 is three saves at a limit of 100.
    final entries = await entriesOf(
      await transaction([
        for (var i = 0; i < 250; i++) post(observation('Patient/p$i')),
      ]),
    );
    expect(entries, hasLength(250));
    final ids = <String>{};
    for (final e in entries) {
      expect((e['response'] as Map)['status'], '201');
      ids.add((e['resource'] as Map)['id'] as String);
    }
    expect(ids, hasLength(250));
    final stored = await db.search(
      resourceType: fhir.R4ResourceType.Observation,
      searchParameters: {},
      count: 1000,
    );
    expect({for (final r in stored) r.id!.valueString}, ids);
  });

  test('each create answers as it did: 201, its Location, its version',
      () async {
    final entries = await entriesOf(
      await transaction([
        post(patient('a')),
        post(observation('Patient/x')),
      ]),
    );
    expect(entries, hasLength(2));
    for (final (i, type) in [(0, 'Patient'), (1, 'Observation')]) {
      final response = entries[i]['response'] as Map;
      final resource = entries[i]['resource'] as Map;
      expect(response['status'], '201');
      expect(resource['resourceType'], type);
      final id = resource['id'] as String;
      expect(
        response['location'] as String,
        endsWith('/$type/$id/_history/1'),
      );
      expect(response['etag'], 'W/"1"');
      expect((resource['meta'] as Map)['versionId'], '1');
      final stored = await db.getResource(
        fhir.R4ResourceType.fromString(type)!,
        id,
      );
      expect(stored?.toJson(), resource);
    }
  });

  test('a conditional create sees a create earlier in the Bundle', () async {
    final entries = await entriesOf(
      await transaction([
        post(patient('m1')),
        post(patient('m1'), ifNoneExist: 'identifier=urn:mrn|m1'),
      ]),
    );
    expect((entries[0]['response'] as Map)['status'], '201');
    expect((entries[1]['response'] as Map)['status'], '200');
    expect(
      (entries[1]['resource'] as Map)['id'],
      (entries[0]['resource'] as Map)['id'],
    );
    final stored = await db.search(
      resourceType: fhir.R4ResourceType.Patient,
      searchParameters: {},
    );
    expect(stored, hasLength(1));
  });

  test('a conditional reference finds a create earlier in the Bundle',
      () async {
    final entries = await entriesOf(
      await transaction([
        post(patient('m2')),
        post(observation('Patient?identifier=urn:mrn|m2')),
      ]),
    );
    final patientId = (entries[0]['resource'] as Map)['id'];
    expect(
      ((entries[1]['resource'] as Map)['subject'] as Map)['reference'],
      'Patient/$patientId',
    );
  });

  test('a search in the Bundle finds its creates', () async {
    final entries = await entriesOf(
      await transaction([
        {
          'request': {'method': 'GET', 'url': 'Observation?status=final'},
        },
        for (var i = 0; i < 3; i++) post(observation('Patient/p$i')),
      ]),
    );
    final searchset = entries[0]['resource'] as Map;
    expect(searchset['total'], 3);
  });

  test('a later entry that fails leaves no create stored', () async {
    final r = await transaction([
      for (var i = 0; i < 3; i++) post(observation('Patient/p$i')),
      {
        'resource': {'resourceType': 'Patient', 'id': 'missing'},
        'request': {
          'method': 'PUT',
          'url': 'Patient/missing',
          'ifMatch': 'W/"7"',
        },
      },
    ]);
    expect(r.statusCode, isNot(200), reason: await r.readAsString());
    final stored = await db.search(
      resourceType: fhir.R4ResourceType.Observation,
      searchParameters: {},
    );
    expect(stored, isEmpty);
  });

  test('a PUT of a create in the same Bundle is refused as overlapping',
      () async {
    const urn = 'urn:uuid:4f1d7c2a-0000-4000-8000-000000000001';
    final r = await transaction([
      post(patient('m3'), fullUrl: urn),
      {
        'resource': patient('m3'),
        'request': {'method': 'PUT', 'url': urn},
      },
    ]);
    expect(r.statusCode, 400, reason: await r.readAsString());
    expect(
      await db.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {},
      ),
      isEmpty,
    );
  });
}
