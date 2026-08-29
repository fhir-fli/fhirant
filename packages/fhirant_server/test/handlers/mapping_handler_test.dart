import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
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

late FhirAntDb db;

Future<Response> post(Object? body) => mappingHandler(
      Request(
        'POST',
        Uri.parse(r'http://localhost:8080/$transform'),
        body: body is String ? body : jsonEncode(body),
      ),
      db,
    );

/// The real published us-core-patient profile, verbatim from
/// `hl7.fhir.us.core#3.1.0`, so the test cannot agree with a mistake of mine
/// about what a profile looks like.
///
/// It is committed under `test/fixtures/` rather than read from
/// `~/.fhir/packages`, because that path exists only on a machine that has run
/// the IG publisher. Read from there, this test **skipped on CI** — the run
/// reported 715 where the same commit reported 716 locally, and the behaviour
/// the fixture exists to prove went unverified in the one place that gates
/// merges.
fhir.StructureDefinition usCorePatientProfile() {
  final file = File('test/fixtures/StructureDefinition-us-core-patient.json');
  return fhir.StructureDefinition.fromJson(
    jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
  );
}

Future<Map<String, dynamic>> bodyOf(Response response) async =>
    jsonDecode(await response.readAsString()) as Map<String, dynamic>;

void main() {
  setUp(() {
    db = FhirAntDb(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
  });

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

    test('a profiled target the server does NOT hold is refused, not guessed',
        () async {
      // Nothing is stored, so the canonical cannot be resolved and the last
      // path segment is not a resource type. Refusing beats inventing one.
      final response = await post({
        'map': mapCopying(
          targetUrl:
              'http://hl7.org/fhir/us/core/StructureDefinition/us-core-patient',
        ),
        'source': {'resourceType': 'Patient', 'id': 'a'},
      });

      expect(response.statusCode, equals(400));
      expect(
        ((await bodyOf(response))['issue'] as List).first['diagnostics'],
        contains('us-core-patient'),
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

    test('a profiled target the server DOES hold resolves to its base type',
        () async {
      final profile = usCorePatientProfile();
      // Prove the fixture is the artefact it claims to be before trusting what
      // the test concludes from it.
      expect(
        profile.url?.valueString,
        equals(
          'http://hl7.org/fhir/us/core/StructureDefinition/us-core-patient',
        ),
      );
      expect(profile.derivation?.valueString, equals('constraint'));
      // structuredefinition.html: type is 1..1, "the type this structure
      // describes". The published profile carries type: "Patient", so once the
      // server holds the definition the target is a Patient, not the profile
      // id. This is the case the last-path-segment reading got wrong.
      expect(profile.type.valueString, equals('Patient'));
      await db.saveResource(profile);

      final response = await post({
        'map': mapCopying(
          targetUrl:
              'http://hl7.org/fhir/us/core/StructureDefinition/us-core-patient',
        ),
        'source': {'resourceType': 'Patient', 'id': 'abc'},
      });

      expect(response.statusCode, equals(200));
      final json = await bodyOf(response);
      expect(json['resourceType'], equals('Patient'));
      expect(json['id'], equals('abc'));
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
