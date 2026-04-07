import 'package:test/test.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:shelf/shelf.dart';
import 'package:fhirant_server/src/handlers/metadata_handler.dart';

void main() {
  group('metadataHandler', () {
    late fhir.CapabilityStatement cs;
    late fhir.CapabilityStatementRest rest;

    setUp(() async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/metadata'),
      );
      final response = metadataHandler(request);
      final body = await response.readAsString();

      // Verify it deserializes as a proper CapabilityStatement
      cs = fhir.CapabilityStatement.fromJsonString(body);
      rest = cs.rest!.first;
    });

    test('deserializes as valid CapabilityStatement', () {
      expect(cs.resourceType, equals(fhir.R4ResourceType.CapabilityStatement));
      expect(cs.status, equals(fhir.PublicationStatus.active));
      expect(cs.kind, equals(fhir.CapabilityStatementKind.instance));
      expect(cs.fhirVersion, equals(fhir.FHIRVersion.value430));
      expect(
        cs.format.map((f) => f.valueString).toList(),
        contains('json'),
      );
    });

    test('software and implementation present', () {
      expect(cs.software!.name.valueString, equals('FHIRant'));
      expect(cs.software!.version!.valueString, equals('1.0.0'));
      expect(cs.implementation!.description.valueString,
          contains('FHIRant'));
    });

    test('patchFormat includes application/json-patch+json', () {
      expect(
        cs.patchFormat!.map((f) => f.valueString).toList(),
        contains('application/json-patch+json'),
      );
    });

    test('security section present with CORS and SMART-on-FHIR', () {
      final security = rest.security!;
      expect(security.cors!.valueBoolean, isTrue);
      expect(
        security.service!.first.coding!.first.code!.valueString,
        equals('SMART-on-FHIR'),
      );
      expect(security.description!.valueString, contains('JWT'));
    });

    test('all 5 compartments declared', () {
      final compartments =
          rest.compartment!.map((c) => c.valueString).toList();
      expect(compartments, contains(
        'http://hl7.org/fhir/CompartmentDefinition/patient',
      ));
      expect(compartments, contains(
        'http://hl7.org/fhir/CompartmentDefinition/encounter',
      ));
      expect(compartments, contains(
        'http://hl7.org/fhir/CompartmentDefinition/practitioner',
      ));
      expect(compartments, contains(
        'http://hl7.org/fhir/CompartmentDefinition/relatedPerson',
      ));
      expect(compartments, contains(
        'http://hl7.org/fhir/CompartmentDefinition/device',
      ));
      expect(compartments, hasLength(5));
    });

    test('system-level interactions include search-system', () {
      final codes = rest.interaction!
          .map((i) => i.code.toString())
          .toList();
      expect(codes, contains('transaction'));
      expect(codes, contains('batch'));
      expect(codes, contains('history-system'));
      expect(codes, contains('search-system'));
    });

    test('system-level operations include validate, fhirpath, transform, export', () {
      final opNames = rest.operation!
          .map((o) => o.name.valueString)
          .toList();
      expect(opNames, contains('validate'));
      expect(opNames, contains('fhirpath'));
      expect(opNames, contains('transform'));
      expect(opNames, contains('export'));
    });

    test('resource interactions include patch and history', () {
      final patient = rest.resource!.firstWhere(
          (r) => r.type.valueString == 'Patient');
      final interactions =
          patient.interaction!.map((i) => i.code.toString()).toList();
      expect(interactions, contains('read'));
      expect(interactions, contains('vread'));
      expect(interactions, contains('update'));
      expect(interactions, contains('patch'));
      expect(interactions, contains('delete'));
      expect(interactions, contains('create'));
      expect(interactions, contains('search-type'));
      expect(interactions, contains('history-instance'));
      expect(interactions, contains('history-type'));
    });

    test('versioning and conditional capabilities set correctly', () {
      final patient = rest.resource!.firstWhere(
          (r) => r.type.valueString == 'Patient');
      expect(patient.versioning, equals(fhir.ResourceVersionPolicy.versioned));
      expect(patient.readHistory!.valueBoolean, isTrue);
      expect(patient.updateCreate!.valueBoolean, isTrue);
      expect(patient.conditionalCreate!.valueBoolean, isTrue);
      expect(patient.conditionalRead,
          equals(fhir.ConditionalReadStatus.fullSupport));
      expect(patient.conditionalUpdate!.valueBoolean, isTrue);
      expect(patient.conditionalDelete,
          equals(fhir.ConditionalDeleteStatus.multiple));
    });

    test('Patient has >10 search params', () {
      final patient = rest.resource!.firstWhere(
          (r) => r.type.valueString == 'Patient');
      // 6 common + 19 Patient-specific
      expect(patient.searchParam!.length, greaterThan(10));
    });

    test('Observation has >4 search params', () {
      final obs = rest.resource!.firstWhere(
          (r) => r.type.valueString == 'Observation');
      // 6 common + 10 Observation-specific
      expect(obs.searchParam!.length, greaterThan(4));
    });

    test('\$everything on Patient but not on Observation', () {
      final patient = rest.resource!.firstWhere(
          (r) => r.type.valueString == 'Patient');
      final patientOps =
          patient.operation!.map((o) => o.name.valueString).toList();
      expect(patientOps, contains('everything'));

      final obs = rest.resource!.firstWhere(
          (r) => r.type.valueString == 'Observation');
      final obsOps =
          obs.operation!.map((o) => o.name.valueString).toList();
      expect(obsOps, isNot(contains('everything')));
    });

    test('\$meta operations on all resources', () {
      final patient = rest.resource!.firstWhere(
          (r) => r.type.valueString == 'Patient');
      final patientOps =
          patient.operation!.map((o) => o.name.valueString).toList();
      expect(patientOps, contains('meta'));
      expect(patientOps, contains('meta-add'));
      expect(patientOps, contains('meta-delete'));

      // Also check a non-annotated type
      final obs = rest.resource!.firstWhere(
          (r) => r.type.valueString == 'Observation');
      final obsOps =
          obs.operation!.map((o) => o.name.valueString).toList();
      expect(obsOps, contains('meta'));
    });

    test('\$export on Patient and Group, not on Observation', () {
      final patient = rest.resource!.firstWhere(
          (r) => r.type.valueString == 'Patient');
      final patientOps =
          patient.operation!.map((o) => o.name.valueString).toList();
      expect(patientOps, contains('export'));

      final group = rest.resource!.firstWhere(
          (r) => r.type.valueString == 'Group');
      final groupOps =
          group.operation!.map((o) => o.name.valueString).toList();
      expect(groupOps, contains('export'));

      final obs = rest.resource!.firstWhere(
          (r) => r.type.valueString == 'Observation');
      final obsOps =
          obs.operation!.map((o) => o.name.valueString).toList();
      expect(obsOps, isNot(contains('export')));
    });

    test('searchInclude and searchRevInclude present for annotated types', () {
      final patient = rest.resource!.firstWhere(
          (r) => r.type.valueString == 'Patient');
      expect(patient.searchInclude, isNotNull);
      expect(patient.searchInclude!.length, greaterThan(0));
      expect(
        patient.searchInclude!.map((s) => s.valueString).toList(),
        contains('Patient:organization'),
      );

      expect(patient.searchRevInclude, isNotNull);
      expect(patient.searchRevInclude!.length, greaterThan(0));
    });

    test('validate operation present per-resource', () {
      final obs = rest.resource!.firstWhere(
          (r) => r.type.valueString == 'Observation');
      final obsOps =
          obs.operation!.map((o) => o.name.valueString).toList();
      expect(obsOps, contains('validate'));
    });

    test('\$document on Composition but not on Patient', () {
      final composition = rest.resource!.firstWhere(
          (r) => r.type.valueString == 'Composition');
      final compOps =
          composition.operation!.map((o) => o.name.valueString).toList();
      expect(compOps, contains('document'));

      final patient = rest.resource!.firstWhere(
          (r) => r.type.valueString == 'Patient');
      final patientOps =
          patient.operation!.map((o) => o.name.valueString).toList();
      expect(patientOps, isNot(contains('document')));
    });

    test('all resource types are present', () {
      final types =
          rest.resource!.map((r) => r.type.valueString).toSet();
      // Spot check
      expect(types, contains('Patient'));
      expect(types, contains('Observation'));
      expect(types, contains('Bundle'));
      expect(types, contains('Practitioner'));
      expect(types, contains('Organization'));
    });
  });
}
