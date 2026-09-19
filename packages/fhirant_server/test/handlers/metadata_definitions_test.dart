// Loads the shipped specification, which takes seconds; well past the 30 s
// default under the whole suite.
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/metadata_handler.dart';
import 'package:fhirant_server/src/utils/spec_loader.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// REVIEW-2026-09-17 C3. The CapabilityStatement cited
/// `OperationDefinition/Practitioner-everything`, `RelatedPerson-everything`
/// and `Device-everything` under hl7.org, and R4B publishes none of them.
/// Every `operation.definition` it cites, at the resource and the system
/// level, must now be an OperationDefinition this server holds once the
/// shipped specification is loaded: HL7's from profiles-resources.ndjson,
/// this server's own from fhirant-operations.ndjson.
void main() {
  late FhirAntDb db;

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
    await loadSpecResources(db, 'assets/fhir_spec');
  });
  tearDown(() => db.close());

  test('every cited operation definition is held by the server', () async {
    final response = await metadataHandler(
      Request('GET', Uri.parse('http://localhost:8080/metadata')),
      db: db,
    );
    expect(response.statusCode, 200);
    final capability = fhir.CapabilityStatement.fromJson(
      jsonDecode(await response.readAsString()) as Map<String, dynamic>,
    );
    final rest = capability.rest!.single;
    final cited = <String>{
      for (final r
          in rest.resource ?? const <fhir.CapabilityStatementResource>[])
        for (final op
            in r.operation ?? const <fhir.CapabilityStatementOperation>[])
          op.definition.valueString!,
      for (final op
          in rest.operation ?? const <fhir.CapabilityStatementOperation>[])
        op.definition.valueString!,
    };
    expect(cited, isNotEmpty);
    final missing = <String>[];
    for (final canonical in cited) {
      final url = canonical.split('|').first;
      final held = await db.search(
        resourceType: fhir.R4ResourceType.OperationDefinition,
        searchParameters: {
          'url': [url],
        },
        count: 1,
      );
      if (held.isEmpty) missing.add(canonical);
    }
    expect(missing, isEmpty, reason: 'cited but not held: $missing');
  });

  test('the three compartments R4B defines no operation for cite this server',
      () async {
    final response = await metadataHandler(
      Request('GET', Uri.parse('http://localhost:8080/metadata')),
      db: db,
    );
    final capability = fhir.CapabilityStatement.fromJson(
      jsonDecode(await response.readAsString()) as Map<String, dynamic>,
    );
    String definitionOf(String type) => capability.rest!.single.resource!
        .firstWhere((r) => r.type.valueString == type)
        .operation!
        .firstWhere((o) => o.name.valueString == 'everything')
        .definition
        .valueString!;
    expect(
      definitionOf('Patient'),
      'http://hl7.org/fhir/OperationDefinition/Patient-everything',
    );
    expect(
      definitionOf('Encounter'),
      'http://hl7.org/fhir/OperationDefinition/Encounter-everything',
    );
    for (final type in ['Practitioner', 'RelatedPerson', 'Device']) {
      expect(
        definitionOf(type),
        'http://fhirfli.dev/fhirant/OperationDefinition/$type-everything',
      );
    }
  });
}
