import 'dart:convert';

import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:fhirant_server/src/handlers/fhirpath_handler.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

class MockRequest extends Mock implements Request {}

void main() {
  setUpAll(() {
    registerFallbackValue(fhir.R4ResourceType.Patient);
  });

  group('fhirPathHandler', () {
    late MockFhirAntDb mockDb;
    late MockRequest mockRequest;

    setUp(() {
      mockDb = MockFhirAntDb();
      mockRequest = MockRequest();
    });

    test('evaluates expression against resource from DB', () async {
      final patient = fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': '123',
        'name': [
          {'family': 'Smith'},
        ],
      });

      when(() => mockRequest.url).thenReturn(
        Uri.parse(
          'fhirpath?expression=Patient.name.family&resourceType=Patient&resourceId=123',
        ),
      );
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '123'),
      ).thenAnswer((_) async => patient);

      final response = await fhirPathHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final resultList = jsonDecode(body) as List;
      expect(resultList, isNotEmpty);
    });

    test('evaluates expression against resource from body', () async {
      final patientJson = jsonEncode({
        'resourceType': 'Patient',
        'id': '456',
        'name': [
          {'family': 'Jones'},
        ],
      });

      when(() => mockRequest.url).thenReturn(
        Uri.parse('fhirpath?expression=Patient.name.family'),
      );
      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => patientJson);

      final response = await fhirPathHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      final resultList = jsonDecode(body) as List;
      expect(resultList, isNotEmpty);
    });

    test('returns 400 when expression missing', () async {
      when(() => mockRequest.url).thenReturn(
        Uri.parse('fhirpath'),
      );

      final response = await fhirPathHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(400));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('OperationOutcome'));
    });

    test('returns 400 for invalid resource type', () async {
      when(() => mockRequest.url).thenReturn(
        Uri.parse(
          'fhirpath?expression=Patient.name.family&resourceType=InvalidType&resourceId=123',
        ),
      );

      final response = await fhirPathHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(400));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('OperationOutcome'));
    });

    test('returns 404 when resource not found', () async {
      when(() => mockRequest.url).thenReturn(
        Uri.parse(
          'fhirpath?expression=Patient.name.family&resourceType=Patient&resourceId=999',
        ),
      );
      when(
        () => mockDb.getResource(fhir.R4ResourceType.Patient, '999'),
      ).thenAnswer((_) async => null);

      final response = await fhirPathHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(404));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('OperationOutcome'));
    });

    test('returns 400 when no resource provided', () async {
      when(() => mockRequest.url).thenReturn(
        Uri.parse('fhirpath?expression=Patient.name.family'),
      );
      when(
        () => mockRequest.readAsString(),
      ).thenAnswer((_) async => '');

      final response = await fhirPathHandler(mockRequest, mockDb);

      expect(response.statusCode, equals(400));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('OperationOutcome'));
    });
  });
}
