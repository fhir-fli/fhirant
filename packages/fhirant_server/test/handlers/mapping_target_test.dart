import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/mapping_handler.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// How `$transform` decides what type to build.
///
/// structuremap.html types `structure.url` as `canonical(StructureDefinition)`
/// and gives NO rule for turning it into a type at execution, so the type is
/// read from the resolved `StructureDefinition.type`. Where the canonical
/// cannot be resolved, the URL's last segment is a guess, and it is only worth
/// making when it names a real resource type: HL7's own published
/// `StructureMap-supplyrequest-transform.json` has the target canonical
/// `http://hl7.org/fhir/StructureDefinition/supplyrequest`, lower case, while
/// the type is `SupplyRequest`.
Future<void> main() async {
  late FhirAntDb db;

  setUp(() {
    db = FhirAntDb(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Map<String, dynamic> mapWithTargets(List<String> targetUrls) => {
        'resourceType': 'StructureMap',
        'id': 'test-map',
        'url': 'http://example.org/StructureMap/test',
        'name': 'Test',
        'status': 'active',
        'structure': [
          {
            'url': 'http://hl7.org/fhir/StructureDefinition/Patient',
            'mode': 'source',
          },
          for (final url in targetUrls) {'url': url, 'mode': 'target'},
        ],
        'group': [
          {
            'name': 'main',
            'typeMode': 'none',
            'input': [
              {'name': 'src', 'mode': 'source'},
              {'name': 'tgt', 'mode': 'target'},
            ],
            'rule': <Map<String, dynamic>>[],
          },
        ],
      };

  Future<Response> transform(Map<String, dynamic> map) => mappingHandler(
        Request(
          'POST',
          Uri.parse(r'http://localhost/$transform'),
          body: jsonEncode({
            'map': map,
            'source': {'resourceType': 'Patient', 'id': 'p1'},
          }),
        ),
        db,
      );

  Future<String> diagnostics(Response response) async {
    final outcome =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    return ((outcome['issue'] as List).first as Map)['diagnostics'] as String;
  }

  test('an unheld profile canonical is refused, not guessed', () async {
    final response = await transform(
      mapWithTargets(const [
        'http://example.org/StructureDefinition/us-core-patient',
      ]),
    );

    expect(response.statusCode, 400);
    final message = await diagnostics(response);
    expect(message, contains('us-core-patient'));
    expect(message, contains('not an R4 resource type'));
  });

  test("HL7's own lower-case canonical is refused rather than guessed",
      () async {
    // StructureMap-supplyrequest-transform.json, from the published package.
    final response = await transform(
      mapWithTargets(['http://hl7.org/fhir/StructureDefinition/supplyrequest']),
    );

    expect(response.statusCode, 400);
    expect(await diagnostics(response), contains('supplyrequest'));
  });

  test('an unresolved canonical whose last segment IS a type still works',
      () async {
    // Nothing is stored, so this exercises the guarded fallback rather than
    // the resolved path.
    final response = await transform(
      mapWithTargets(['http://hl7.org/fhir/StructureDefinition/Basic']),
    );

    // Basic requires `code`, so the transform itself fails — but it got as far
    // as building the target, which is what this test is about.
    expect(response.statusCode, isNot(400));
  });

  test('several target structures of different types are refused', () async {
    final response = await transform(
      mapWithTargets([
        'http://hl7.org/fhir/StructureDefinition/Patient',
        'http://hl7.org/fhir/StructureDefinition/Basic',
      ]),
    );

    expect(response.statusCode, 400);
    final message = await diagnostics(response);
    expect(message, contains('more than one type'));
    expect(message, contains('Basic, Patient'));
  });

  test('several target structures of the SAME type are unambiguous', () async {
    final response = await transform(
      mapWithTargets([
        'http://hl7.org/fhir/StructureDefinition/Patient',
        'http://hl7.org/fhir/StructureDefinition/Patient',
      ]),
    );

    expect(response.statusCode, isNot(400));
  });

  test('a resolved profile still gives its base type', () async {
    await db.saveResource(
      fhir.StructureDefinition.fromJson({
        'resourceType': 'StructureDefinition',
        'id': 'us-core-patient',
        'url': 'http://example.org/StructureDefinition/us-core-patient',
        'name': 'UsCorePatient',
        'status': 'active',
        'kind': 'resource',
        'abstract': false,
        'type': 'Patient',
        'baseDefinition': 'http://hl7.org/fhir/StructureDefinition/Patient',
        'derivation': 'constraint',
      }),
    );

    final response = await transform(
      mapWithTargets(const [
        'http://example.org/StructureDefinition/us-core-patient',
      ]),
    );

    expect(response.statusCode, isNot(400));
  });
}
