import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:fhirant_server/src/handlers/resource_handler.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

class MockRequest extends Mock implements Request {}

void main() {
  setUpAll(() {
    registerFallbackValue(fhir.R4ResourceType.Patient);
  });

  group('getResourceByIdHandler', () {
    late MockFhirAntDb mockDb;
    late MockRequest mockRequest;

    setUp(() {
      mockDb = MockFhirAntDb();
      mockRequest = MockRequest();
    });

    test('returns 200 with resource when found', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'name': [
          {'family': 'Smith'},
        ],
      });

      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => patient);

      final response = await getResourceByIdHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('Patient'));
      expect(json['id'], equals('123'));
      verify(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).called(1);
    });

    test('returns 404 when not found', () async {
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => null);

      final response = await getResourceByIdHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(404));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['error'], equals('Resource not found'));
    });

    test('returns 400 for invalid resource type', () async {
      final response = await getResourceByIdHandler(
        mockRequest,
        'InvalidType',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(400));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('OperationOutcome'));
      verifyNever(() => mockDb.getResource(any(), any()));
    });

    test('returns 500 when database throws', () async {
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenThrow(Exception('Database error'));

      final response = await getResourceByIdHandler(
        mockRequest,
        'Patient',
        '123',
        mockDb,
      );

      expect(response.statusCode, equals(500));
    });
  });
}
