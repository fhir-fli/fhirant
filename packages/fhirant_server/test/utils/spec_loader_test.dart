import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/spec_loader.dart';
import 'package:test/test.dart';

/// REVIEW-2026-09-06 finding 43: the specification loads from an asset
/// bundle the way it loads from the CLI's directory, in chunks, once.
void main() {
  late FhirAntDb db;

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
  });

  tearDown(() => db.close());

  String line(Map<String, dynamic> json) => jsonEncode(json);

  final assets = <String, String>{
    'assets/fhir_spec/codesystems.ndjson': [
      for (var i = 0; i < 250; i++)
        line({
          'resourceType': 'CodeSystem',
          'id': 'cs$i',
          'url': 'http://example.org/cs/$i',
          'status': 'active',
          'content': 'complete',
        }),
    ].join('\n'),
    'assets/fhir_spec/valuesets.ndjson': [
      line({
        'resourceType': 'ValueSet',
        'id': 'vs1',
        'url': 'http://example.org/vs/1',
        'status': 'active',
      }),
      '',
      'not json',
      line({
        'resourceType': 'ValueSet',
        'id': 'vs2',
        'url': 'http://example.org/vs/2',
        'status': 'active',
      }),
    ].join('\n'),
    'assets/fhir_spec/README.md': 'not an ndjson asset',
  };

  Future<void> load() => loadSpecResourcesFromAssets(
        db,
        assetKeys: assets.keys,
        loadBytes: (key) async =>
            ByteData.sublistView(Uint8List.fromList(utf8.encode(assets[key]!))),
      );

  test('every parseable line of every .ndjson asset is stored', () async {
    await load();
    expect(await db.getResourceCount(fhir.R4ResourceType.CodeSystem), 250);
    expect(await db.getResourceCount(fhir.R4ResourceType.ValueSet), 2);
    final vs = await db.getResource(fhir.R4ResourceType.ValueSet, 'vs2');
    expect((vs! as fhir.ValueSet).url?.valueString, 'http://example.org/vs/2');
  });

  test('every loaded resource is tagged spec and is stored once', () async {
    await load();
    final cs = await db.getResource(fhir.R4ResourceType.CodeSystem, 'cs7');
    expect(isSpecResource(cs!), isTrue);
    expect(cs.meta!.versionId!.valueString, '1');
    // The history interaction answers the current version; the table
    // behind it holds no second copy (fhir_r4_db schema 14).
    Future<int> historyRows() async => (await db
            .customSelect(
              "SELECT count(*) AS c FROM resources_history WHERE id = 'cs7'",
            )
            .getSingle())
        .read<int>('c');
    expect(
      await db.getHistory(fhir.R4ResourceType.CodeSystem, 'cs7'),
      hasLength(1),
    );
    expect(await historyRows(), 0);
    // A later save of a specification resource moves the replaced version
    // into history as any save does.
    await db.saveResource(cs);
    expect(
      await db.getHistory(fhir.R4ResourceType.CodeSystem, 'cs7'),
      hasLength(2),
    );
    expect(await historyRows(), 1);
  });

  test('a store that already holds CodeSystems is left alone', () async {
    await db.saveResource(
      fhir.CodeSystem.fromJson({
        'resourceType': 'CodeSystem',
        'id': 'mine',
        'status': 'active',
        'content': 'complete',
      }),
    );
    await load();
    expect(await db.getResourceCount(fhir.R4ResourceType.CodeSystem), 1);
    expect(await db.getResourceCount(fhir.R4ResourceType.ValueSet), 0);
  });

  test('loadSpecLines saves in chunks and counts what failed', () async {
    final (loaded, errors) = await loadSpecLines(
      db,
      Stream.fromIterable([
        for (var i = 0; i < 101; i++)
          line({
            'resourceType': 'NamingSystem',
            'id': 'ns$i',
            'name': 'ns$i',
            'status': 'active',
            'kind': 'identifier',
            'date': '2026-01-01',
            'uniqueId': [
              {'type': 'uri', 'value': 'http://example.org/ns/$i'},
            ],
          }),
        '{"resourceType":"NamingSystem"',
      ]),
      'namingsystems.ndjson',
    );
    expect(loaded, 101);
    expect(errors, 1);
    expect(await db.getResourceCount(fhir.R4ResourceType.NamingSystem), 101);
  });

  // REVIEW-2026-09-17 S3b. The load runs whenever the store holds no
  // CodeSystem: on a first start, and again after a load that was
  // interrupted before valuesets.ndjson, the last file. The app runs it
  // unawaited beside a live server. It saved over whatever it found, so a
  // resource a client had written since (an edit of a StructureDefinition,
  // a restored backup) became history under the shipped copy, tagged as
  // the server's again and so left out of the next backup.
  group('the load fills what is missing and overwrites nothing', () {
    Map<String, dynamic> definition(String id, String title) => {
          'resourceType': 'NamingSystem',
          'id': id,
          'name': title,
          'status': 'active',
          'kind': 'identifier',
          'date': '2026-01-01',
          'uniqueId': [
            {'type': 'uri', 'value': 'http://example.org/ns/$id'},
          ],
        };

    Future<fhir.NamingSystem> stored(String id) async =>
        (await db.getResource(fhir.R4ResourceType.NamingSystem, id))!
            as fhir.NamingSystem;

    test("a resource a client wrote is left as the client's", () async {
      await db.saveResource(
        fhir.Resource.fromJson(definition('a', 'the deployment edit')),
      );
      final (loaded, errors) = await loadSpecLines(
        db,
        Stream.fromIterable([
          line(definition('a', 'as shipped')),
          line(definition('b', 'as shipped')),
        ]),
        'namingsystems.ndjson',
      );
      expect((loaded, errors), (1, 0));
      final a = await stored('a');
      expect(a.name.valueString, 'the deployment edit');
      expect(a.meta!.versionId!.valueString, '1');
      expect(isSpecResource(a), isFalse);
      expect(isSpecResource(await stored('b')), isTrue);
    });

    test('a second run over a loaded file writes no second version', () async {
      Stream<String> file() => Stream.fromIterable([
            line(definition('a', 'as shipped')),
            line(definition('b', 'as shipped')),
          ]);
      expect(await loadSpecLines(db, file(), 'x.ndjson'), (2, 0));
      expect(await loadSpecLines(db, file(), 'x.ndjson'), (0, 0));
      expect((await stored('a')).meta!.versionId!.valueString, '1');
    });
  });
}
