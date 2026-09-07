import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/resource_handler.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// R4 3.1.1.6: "the server SHALL return the parameters that were actually
/// used to process the search ... these parameters are encoded in the self
/// link". R4 3.1.1.7: a `_query` value the server does not recognise SHALL be
/// refused. R4 3.1.1.5.3: `_count=0` "is treated the same as _summary=count".
void main() {
  late FhirAntDb db;

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    for (final (id, given) in [
      ('p1', ['Anna', 'Beth']),
      ('p2', ['Anna', 'Beth']),
      ('p3', ['Anna']),
    ]) {
      await db.saveResource(
        fhir.Patient.fromJson({
          'resourceType': 'Patient',
          'id': id,
          'gender': 'female',
          'name': [
            {'given': given},
          ],
        }),
      );
    }
    await db.saveResource(
      fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': 'o1',
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '8867-4'},
          ],
        },
        'effectiveDateTime': '2024-05-06T12:00:00Z',
      }),
    );
  });
  tearDown(() async => db.close());

  Future<Response> get(
    String type,
    String query, {
    Map<String, String> headers = const {},
  }) =>
      getResourcesHandler(
        Request(
          'GET',
          Uri.parse('http://localhost:8080/$type?$query'),
          headers: headers,
        ),
        type,
        db,
      );

  Future<Map<String, dynamic>> bundle(Response response) async {
    expect(response.statusCode, equals(200));
    return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
  }

  String? link(Map<String, dynamic> b, String relation) {
    for (final l in (b['link'] as List?) ?? []) {
      if ((l as Map)['relation'] == relation) return l['url'] as String;
    }
    return null;
  }

  group('_query', () {
    test('any value is refused: this server defines no named queries',
        () async {
      final response = await get('Patient', '_query=current-patients');
      expect(response.statusCode, equals(400));
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['resourceType'], equals('OperationOutcome'));
      final issue = (body['issue'] as List).first as Map<String, dynamic>;
      expect(issue['code'], equals('not-supported'));
      expect(issue['diagnostics'], contains('current-patients'));
    });

    test('refused under lenient handling too: it is a SHALL', () async {
      final response = await get(
        'Patient',
        '_query=x',
        headers: {'Prefer': 'handling=lenient'},
      );
      expect(response.statusCode, equals(400));
    });

    test('through POST _search as well', () async {
      final response = await postSearchHandler(
        Request(
          'POST',
          Uri.parse('http://localhost:8080/Patient/_search'),
          body: '_query=x',
          headers: {'content-type': 'application/x-www-form-urlencoded'},
        ),
        'Patient',
        db,
      );
      expect(response.statusCode, equals(400));
    });
  });

  group('_count=0', () {
    test('is a count: total, no entries', () async {
      final b = await bundle(await get('Patient', 'gender=female&_count=0'));
      expect(b['total'], equals(3));
      expect(b['entry'], isNull);
    });

    test('the count bundle carries a self link', () async {
      final b = await bundle(await get('Patient', 'gender=female&_count=0'));
      expect(link(b, 'self'), contains('gender=female'));
    });
  });

  group('self link', () {
    test('carries the parameters that were used', () async {
      final b = await bundle(await get('Patient', 'gender=female&_count=2'));
      final self = link(b, 'self')!;
      expect(self, contains('gender=female'));
      expect(self, contains('_count=2'));
    });

    test('drops a parameter the store has no definition for', () async {
      // Lenient (the default): `gendr` is ignored (3.1.1.3), the search runs
      // on `gender` alone, and the self link says so.
      final b = await bundle(await get('Patient', 'gender=female&gendr=male'));
      expect((b['entry'] as List).length, equals(3));
      final self = link(b, 'self')!;
      expect(self, contains('gender=female'));
      expect(self, isNot(contains('gendr')));
    });

    test('drops an unparseable _has and an undefined _sort rule', () async {
      final b = await bundle(
        await get('Patient', 'gender=female&_has:Nonsense&_sort=gender,nope'),
      );
      final self = link(b, 'self')!;
      expect(self, isNot(contains('_has')));
      expect(self, contains('_sort=gender'));
      expect(self, isNot(contains('nope')));
    });

    test("keeps a modifier and a chain, which are the store's to judge",
        () async {
      final b = await bundle(
        await get('Patient', 'gender:not=male&general-practitioner.name=x'),
      );
      final self = link(b, 'self')!;
      expect(self, contains('gender%3Anot=male'));
      expect(self, contains('general-practitioner.name=x'));
    });

    test('the empty bundle carries the same self link', () async {
      final b = await bundle(await get('Patient', 'gender=male&gendr=female'));
      expect(b['entry'], isNull);
      final self = link(b, 'self')!;
      expect(self, contains('gender=male'));
      expect(self, isNot(contains('gendr')));
    });
  });

  group('Prefer: handling=strict', () {
    test('refuses an undefined parameter whether or not it starts with _',
        () async {
      final response = await get(
        'Patient',
        'gendr=female',
        headers: {'Prefer': 'handling=strict'},
      );
      expect(response.statusCode, equals(400));
      final body = await response.readAsString();
      expect(body, contains('gendr'));
    });

    test('accepts a defined parameter with a modifier', () async {
      final response = await get(
        'Patient',
        'gender:not=male&_id=p1',
        headers: {'Prefer': 'handling=strict'},
      );
      expect(response.statusCode, equals(200));
    });
  });

  group('paging links', () {
    test('a repeated parameter survives into next and last', () async {
      // `given=Anna&given=Beth` is an AND (3.1.1.4.17). `queryParameters`
      // keeps only the last value, so the next page used to run
      // `given=Beth` and could return a different set.
      final b =
          await bundle(await get('Patient', 'given=Anna&given=Beth&_count=1'));
      expect(b['total'], equals(2));
      final next = link(b, 'next')!;
      expect(next, contains('given=Anna'));
      expect(next, contains('given=Beth'));
      expect(next, contains('_offset=1'));
      final last = link(b, 'last')!;
      expect(last, contains('given=Anna'));
      expect(last, contains('given=Beth'));
    });

    test('previous is present past the first page and clamps at 0', () async {
      final b = await bundle(
        await get('Patient', 'gender=female&_count=2&_offset=1'),
      );
      expect(link(b, 'previous'), contains('_offset=0'));
      expect(link(b, 'first'), contains('_offset=0'));
    });

    test('links drop an ignored parameter too', () async {
      final b = await bundle(
        await get('Patient', 'gender=female&gendr=x&_count=1'),
      );
      expect(link(b, 'next'), isNot(contains('gendr')));
    });
  });

  test('an escaped colon in a date value is decoded (3.1.1.4.7 SHALL)',
      () async {
    final b = await bundle(
      await get('Observation', 'date=ge2024-05-06T10%3A00%3A00Z'),
    );
    expect((b['entry'] as List).length, equals(1));
    // And a value that excludes it, spelled the same way.
    final none = await bundle(
      await get('Observation', 'date=gt2024-05-06T13%3A00%3A00Z'),
    );
    expect(none['entry'], isNull);
  });
}
