import 'dart:convert';

import 'package:fhirant_server/src/handlers/mapping_handler.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// `$transform` is advertised in the CapabilityStatement and gated by a SMART
/// scope, and until 2026-08-29 it had no tests at all. It returned 500 on every
/// real transform, because the handler passed a null target to the mapping
/// engine and the engine cannot invent one.
///
/// The map below is the shape R4 structuremap.html describes: a `structure`
/// entry per model with the target's canonical URL, and a group whose rule
/// copies one element across.
Map<String, dynamic> mapCopying({
  required String targetUrl,
  String element = 'id',
}) =>
    <String, dynamic>{
      'resourceType': 'StructureMap',
      'url': 'http://example.org/StructureMap/test',
      'name': 'Test',
      'status': 'draft',
      'structure': [
        {
          'url': 'http://hl7.org/fhir/StructureDefinition/Patient',
          'mode': 'source',
          'alias': 'src',
        },
        {'url': targetUrl, 'mode': 'target', 'alias': 'tgt'},
      ],
      'group': [
        {
          'name': 'main',
          'typeMode': 'none',
          'input': [
            {'name': 'source', 'type': 'src', 'mode': 'source'},
            {'name': 'target', 'type': 'tgt', 'mode': 'target'},
          ],
          'rule': [
            {
              'name': 'copy$element',
              'source': [
                {'context': 'source', 'element': element, 'variable': 'v'},
              ],
              'target': [
                {
                  'context': 'target',
                  'contextType': 'variable',
                  'element': element,
                  'transform': 'copy',
                  'parameter': [
                    {'valueId': 'v'},
                  ],
                },
              ],
            },
          ],
        },
      ],
    };

Future<Response> post(Object? body) => mappingHandler(
      Request(
        'POST',
        Uri.parse(r'http://localhost:8080/$transform'),
        body: body is String ? body : jsonEncode(body),
      ),
    );

Future<Map<String, dynamic>> bodyOf(Response response) async =>
    jsonDecode(await response.readAsString()) as Map<String, dynamic>;

void main() {
  group(r'$transform rejects a request it cannot act on', () {
    test('empty body', () async {
      final response = await post('');
      expect(response.statusCode, equals(400));
      final json = await bodyOf(response);
      expect(json['resourceType'], equals('OperationOutcome'));
      expect((json['issue'] as List).first['diagnostics'], contains('empty'));
    });

    test('unparseable JSON', () async {
      final response = await post('not json{{{');
      expect(response.statusCode, equals(400));
      expect(
        ((await bodyOf(response))['issue'] as List).first['diagnostics'],
        contains('Invalid JSON'),
      );
    });

    test('no map', () async {
      final response = await post({
        'source': {'resourceType': 'Patient', 'id': 'a'},
      });
      expect(response.statusCode, equals(400));
      expect(
        ((await bodyOf(response))['issue'] as List).first['diagnostics'],
        contains('map'),
      );
    });

    test('no source', () async {
      final response = await post({
        'map': mapCopying(
          targetUrl: 'http://hl7.org/fhir/StructureDefinition/Patient',
        ),
      });
      expect(response.statusCode, equals(400));
      expect(
        ((await bodyOf(response))['issue'] as List).first['diagnostics'],
        contains('source'),
      );
    });

    test("a map with no target structure is the caller's error, not a 500",
        () async {
      final map = mapCopying(
        targetUrl: 'http://hl7.org/fhir/StructureDefinition/Patient',
      );
      (map['structure'] as List).removeWhere(
        (dynamic s) => (s as Map)['mode'] == 'target',
      );
      final response = await post({
        'map': map,
        'source': {'resourceType': 'Patient', 'id': 'a'},
      });
      expect(response.statusCode, equals(400));
      expect(
        ((await bodyOf(response))['issue'] as List).first['diagnostics'],
        contains('target'),
      );
    });

    test('a target this server cannot build is 400, not 500', () async {
      final response = await post({
        'map': mapCopying(targetUrl: 'http://example.org/logical/TCustom'),
        'source': {'resourceType': 'Patient', 'id': 'a'},
      });
      expect(response.statusCode, equals(400));
      final json = await bodyOf(response);
      expect((json['issue'] as List).first['code'], equals('not-supported'));
      expect(
        (json['issue'] as List).first['diagnostics'],
        contains('TCustom'),
      );
    });
  });

  group(r'$transform performs the transform', () {
    test('copies an element into a new target resource', () async {
      final response = await post({
        'map': mapCopying(
          targetUrl: 'http://hl7.org/fhir/StructureDefinition/Patient',
        ),
        'source': {'resourceType': 'Patient', 'id': 'abc'},
      });

      expect(response.statusCode, equals(200));
      final json = await bodyOf(response);
      expect(json['resourceType'], equals('Patient'));
      expect(json['id'], equals('abc'));
    });

    test('the target is a fresh instance, not the source', () async {
      final response = await post({
        'map': mapCopying(
          targetUrl: 'http://hl7.org/fhir/StructureDefinition/Patient',
        ),
        'source': {
          'resourceType': 'Patient',
          'id': 'abc',
          'active': true,
        },
      });

      expect(response.statusCode, equals(200));
      final json = await bodyOf(response);
      expect(json['id'], equals('abc'));
      expect(
        json.containsKey('active'),
        isFalse,
        reason: 'the map copies id only, so active must not carry over',
      );
    });

    test('transforms across resource types', () async {
      final response = await post({
        'map': mapCopying(
          targetUrl: 'http://hl7.org/fhir/StructureDefinition/Practitioner',
        ),
        'source': {'resourceType': 'Patient', 'id': 'xyz'},
      });

      expect(response.statusCode, equals(200));
      final json = await bodyOf(response);
      expect(json['resourceType'], equals('Practitioner'));
      expect(json['id'], equals('xyz'));
    });

    test('a map that cannot produce a valid target is 422, never 200',
        () async {
      // Observation.status and Observation.code are 1..1. A map that sets
      // neither cannot produce an Observation, and the engine reports that by
      // returning an OperationOutcome rather than throwing.
      final response = await post({
        'map': mapCopying(
          targetUrl: 'http://hl7.org/fhir/StructureDefinition/Observation',
        ),
        'source': {'resourceType': 'Patient', 'id': 'xyz'},
      });

      expect(response.statusCode, equals(422));
      final json = await bodyOf(response);
      expect(json['resourceType'], equals('OperationOutcome'));
      expect(json['issue'] as List, isNotEmpty);
    });
  });
}
