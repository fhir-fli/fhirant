import 'dart:convert';

import 'package:test/test.dart';
import 'package:shelf/shelf.dart';
import 'package:fhirant_server/src/handlers/metadata_handler.dart';

void main() {
  group('metadataHandler', () {
    late Map<String, dynamic> capability;
    late Map<String, dynamic> rest;

    setUp(() async {
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/metadata'),
      );
      final response = metadataHandler(request);
      final body = await response.readAsString();
      capability = jsonDecode(body) as Map<String, dynamic>;
      rest = (capability['rest'] as List).first as Map<String, dynamic>;
    });

    test('security section present with CORS and JWT Bearer', () {
      final security = rest['security'] as Map<String, dynamic>;
      expect(security['cors'], isTrue);
      final services = security['service'] as List;
      expect(services, isNotEmpty);
      final coding =
          ((services.first as Map)['coding'] as List).first as Map;
      expect(coding['code'], equals('SMART-on-FHIR'));
      expect(security['description'], contains('JWT'));
    });

    test('operations include validate, fhirpath, transform', () {
      final operations = rest['operation'] as List;
      final opNames =
          operations.map((o) => (o as Map)['name'] as String).toList();
      expect(opNames, contains('validate'));
      expect(opNames, contains('fhirpath'));
      expect(opNames, contains('transform'));
    });

    test('resource interactions include patch and history', () {
      final resources = rest['resource'] as List;
      final patient = resources.firstWhere(
          (r) => (r as Map)['type'] == 'Patient') as Map<String, dynamic>;
      final interactions = (patient['interaction'] as List)
          .map((i) => (i as Map)['code'] as String)
          .toList();
      expect(interactions, contains('patch'));
      expect(interactions, contains('history-instance'));
      expect(interactions, contains('history-type'));
    });

    test('patchFormat includes application/json-patch+json', () {
      final patchFormats = capability['patchFormat'] as List;
      expect(patchFormats, contains('application/json-patch+json'));
    });

    test('versioning and history capabilities set', () {
      final resources = rest['resource'] as List;
      final patient = resources.firstWhere(
          (r) => (r as Map)['type'] == 'Patient') as Map<String, dynamic>;
      expect(patient['versioning'], equals('versioned'));
      expect(patient['readHistory'], isTrue);
      expect(patient['updateCreate'], isTrue);
    });

    test('conditional operations documented', () {
      final resources = rest['resource'] as List;
      final patient = resources.firstWhere(
          (r) => (r as Map)['type'] == 'Patient') as Map<String, dynamic>;
      expect(patient['conditionalCreate'], isTrue);
      expect(patient['conditionalRead'], equals('modified-since'));
      expect(patient['conditionalUpdate'], isTrue);
      expect(patient['conditionalDelete'], equals('single'));
    });

    test('system-level interactions include transaction and batch', () {
      final interactions = rest['interaction'] as List;
      final codes = interactions
          .map((i) => (i as Map)['code'] as String)
          .toList();
      expect(codes, contains('transaction'));
      expect(codes, contains('batch'));
      expect(codes, contains('history-system'));
    });
  });
}
