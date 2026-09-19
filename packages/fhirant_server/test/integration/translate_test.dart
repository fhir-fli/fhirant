import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-17 C7: `$translate` returned the first target only.
///
/// OperationDefinition ConceptMap-translate (bundled profiles-resources.ndjson,
/// verbatim): `match` is 0..*, "Note that there may be multiple matches of
/// equal or differing equivalence, and the matches may include equivalence
/// values that mean that there is no match"; `result` is "True if the concept
/// could be translated successfully. The value can only be true if at least
/// one returned match has an equivalence which is not unmatched or disjoint".
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;
  late Directory exportDir;

  setUp(() async {
    exportDir = await Directory.systemTemp.createTemp('translate');
    final server = await createTestServer(exportDir: exportDir.path);
    db = server.db;
    handler = server.handler;
    token = await issueTestToken(
      db,
      username: 'admin',
      role: 'admin',
      scopes: ['system/*.*'],
    );
    await db.saveResource(
      fhir.ConceptMap.fromJson({
        'resourceType': 'ConceptMap',
        'id': 'cm',
        'url': 'http://example.org/ConceptMap/cm',
        'status': 'active',
        'group': [
          {
            'source': 'http://example.org/cs/a',
            'target': 'http://example.org/cs/b',
            'element': [
              {
                'code': 'a1',
                'target': [
                  {'code': 'b1', 'equivalence': 'equivalent'},
                  {
                    'code': 'b2',
                    'equivalence': 'wider',
                    'product': [
                      {
                        'property': 'http://example.org/property/site',
                        'system': 'http://example.org/cs/site',
                        'value': 'left',
                      },
                    ],
                  },
                ],
              },
              {
                'code': 'a2',
                'target': [
                  {'equivalence': 'unmatched'},
                ],
              },
            ],
          },
          {
            'source': 'http://example.org/cs/a',
            'target': 'http://example.org/cs/c',
            'element': [
              {
                'code': 'a1',
                'target': [
                  {'code': 'c1', 'equivalence': 'inexact'},
                ],
              },
            ],
          },
        ],
      }),
    );
  });

  tearDown(() async {
    await db.close();
    await exportDir.delete(recursive: true);
  });

  Future<Map<String, dynamic>> translate(String code) async {
    final r = await handler(
      testRequest(
        'GET',
        r'/ConceptMap/cm/$translate?system=http://example.org/cs/a&code='
            '$code',
        authToken: token,
      ),
    );
    final text = await r.readAsString();
    expect(r.statusCode, 200, reason: text);
    return jsonDecode(text) as Map<String, dynamic>;
  }

  List<Map<String, dynamic>> partsOf(List<dynamic> parameters, String name) =>
      parameters
          .cast<Map<String, dynamic>>()
          .where((p) => p['name'] == name)
          .toList();

  test('every target across every matching group is a match', () async {
    final out = await translate('a1');
    final parameters = out['parameter'] as List;
    expect(partsOf(parameters, 'result').single['valueBoolean'], isTrue);
    final matches = partsOf(parameters, 'match');
    expect(matches, hasLength(3));
    final concepts = [
      for (final m in matches)
        partsOf(m['part'] as List, 'concept').single['valueCoding']['code'],
    ];
    expect(concepts, ['b1', 'b2', 'c1']);
    final equivalences = [
      for (final m in matches)
        partsOf(m['part'] as List, 'equivalence').single['valueCode'],
    ];
    expect(equivalences, ['equivalent', 'wider', 'inexact']);
    for (final m in matches) {
      expect(
        partsOf(m['part'] as List, 'source').single['valueUri'],
        'http://example.org/ConceptMap/cm',
      );
    }
    final product = partsOf(matches[1]['part'] as List, 'product').single;
    expect(
      partsOf(product['part'] as List, 'element').single['valueUri'],
      'http://example.org/property/site',
    );
    expect(
      partsOf(product['part'] as List, 'concept').single['valueCoding']['code'],
      'left',
    );
  });

  test('an unmatched target is a match that does not make result true',
      () async {
    final out = await translate('a2');
    final parameters = out['parameter'] as List;
    expect(partsOf(parameters, 'result').single['valueBoolean'], isFalse);
    final match = partsOf(parameters, 'match').single;
    expect(
      partsOf(match['part'] as List, 'equivalence').single['valueCode'],
      'unmatched',
    );
    expect(partsOf(match['part'] as List, 'concept'), isEmpty);
  });

  test('a code the map does not carry: result false, no match', () async {
    final out = await translate('nope');
    final parameters = out['parameter'] as List;
    expect(partsOf(parameters, 'result').single['valueBoolean'], isFalse);
    expect(partsOf(parameters, 'match'), isEmpty);
  });
}
