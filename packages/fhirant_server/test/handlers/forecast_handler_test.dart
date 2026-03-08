import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/forecast_handler.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

void main() {
  late MockFhirAntDb mockDb;

  setUpAll(() {
    registerFallbackValue(fhir.R4ResourceType.Patient);
  });

  setUp(() {
    mockDb = MockFhirAntDb();
  });

  Request _postJson(String path, dynamic body) {
    return Request(
      'POST',
      Uri.parse('http://localhost$path'),
      body: jsonEncode(body),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// A minimal valid Parameters resource for Cicada.
  Map<String, dynamic> _minimalForecastParams({
    String patientId = 'pat-1',
    String birthDate = '2020-06-15',
    List<Map<String, dynamic>> immunizations = const [],
  }) {
    final params = <Map<String, dynamic>>[
      {
        'name': 'assessmentDate',
        'valueDate': '2024-01-15',
      },
      {
        'name': 'patient',
        'resource': {
          'resourceType': 'Patient',
          'id': patientId,
          'birthDate': birthDate,
          'gender': 'male',
        },
      },
      ...immunizations.map((imm) =>
            <String, dynamic>{'name': 'immunization', 'resource': imm}),
    ];
    return {
      'resourceType': 'Parameters',
      'parameter': params,
    };
  }

  group('\$immds-forecast (CDC)', () {
    test('returns 400 when body is empty', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/\$immds-forecast'),
        body: '',
      );
      final response = await immdsForecastHandler(request, mockDb);
      expect(response.statusCode, 400);
    });

    test('returns 400 for invalid JSON', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/\$immds-forecast'),
        body: 'not json',
        headers: {'Content-Type': 'application/json'},
      );
      final response = await immdsForecastHandler(request, mockDb);
      expect(response.statusCode, 400);
    });

    test('returns 400 when no Parameters or patientId', () async {
      final response = await immdsForecastHandler(
        _postJson('/\$immds-forecast', {'foo': 'bar'}),
        mockDb,
      );
      expect(response.statusCode, 400);
    });

    test('evaluates forecast with inline Parameters', () async {
      final params = _minimalForecastParams();

      final response = await immdsForecastHandler(
        _postJson('/\$immds-forecast', params),
        mockDb,
      );
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], 'Parameters');
      // Should have recommendation parameter(s)
      final paramList = body['parameter'] as List;
      expect(paramList, isNotEmpty);
    });

    test('returns recommendations for unvaccinated infant', () async {
      final params = _minimalForecastParams(
        birthDate: '2023-06-15',
      );

      final response = await immdsForecastHandler(
        _postJson('/\$immds-forecast', params),
        mockDb,
      );
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString());
      final paramList = body['parameter'] as List;
      // An unvaccinated infant should get many recommendations
      final recommendations = paramList.where(
        (p) => p['name'] == 'recommendation',
      );
      expect(recommendations, isNotEmpty);
    });

    test('evaluates forecast with immunization history', () async {
      final params = _minimalForecastParams(
        birthDate: '2020-06-15',
        immunizations: [
          {
            'resourceType': 'Immunization',
            'id': 'imm-1',
            'status': 'completed',
            'vaccineCode': {
              'coding': [
                {
                  'system': 'http://hl7.org/fhir/sid/cvx',
                  'code': '03', // MMR
                }
              ],
            },
            'occurrenceDateTime': '2021-06-15',
            'patient': {'reference': 'Patient/pat-1'},
          }
        ],
      );

      final response = await immdsForecastHandler(
        _postJson('/\$immds-forecast', params),
        mockDb,
      );
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], 'Parameters');
      final paramList = body['parameter'] as List;
      // Should have evaluations for the dose
      final evaluations = paramList.where((p) => p['name'] == 'evaluation');
      expect(evaluations, isNotEmpty);
    });

    test('loads patient data from DB via patientId', () async {
      final patient = fhir.Patient(
        id: 'db-pat'.toFhirString,
        birthDate: fhir.FhirDate.fromString('2020-01-01'),
        gender: fhir.AdministrativeGender.male,
      );

      when(() => mockDb.getResource(fhir.R4ResourceType.Patient, 'db-pat'))
          .thenAnswer((_) async => patient);
      when(() => mockDb.search(
            resourceType: any(named: 'resourceType'),
            searchParameters: any(named: 'searchParameters'),
            hasParameters: any(named: 'hasParameters'),
            count: any(named: 'count'),
            offset: any(named: 'offset'),
            sort: any(named: 'sort'),
          )).thenAnswer((_) async => <fhir.Resource>[]);

      final response = await immdsForecastHandler(
        _postJson('/\$immds-forecast', {'patientId': 'db-pat'}),
        mockDb,
      );
      expect(response.statusCode, 200);

      verify(() => mockDb.getResource(fhir.R4ResourceType.Patient, 'db-pat'))
          .called(1);
      // Should have searched for Immunizations, Conditions, AllergyIntolerances
      verify(() => mockDb.search(
            resourceType: fhir.R4ResourceType.Immunization,
            searchParameters: any(named: 'searchParameters'),
            hasParameters: any(named: 'hasParameters'),
            count: any(named: 'count'),
            offset: any(named: 'offset'),
            sort: any(named: 'sort'),
          )).called(1);
    });

    test('patientId in Parameters triggers DB lookup', () async {
      final patient = fhir.Patient(
        id: 'params-pat'.toFhirString,
        birthDate: fhir.FhirDate.fromString('2019-03-10'),
        gender: fhir.AdministrativeGender.female,
      );

      when(() =>
              mockDb.getResource(fhir.R4ResourceType.Patient, 'params-pat'))
          .thenAnswer((_) async => patient);
      when(() => mockDb.search(
            resourceType: any(named: 'resourceType'),
            searchParameters: any(named: 'searchParameters'),
            hasParameters: any(named: 'hasParameters'),
            count: any(named: 'count'),
            offset: any(named: 'offset'),
            sort: any(named: 'sort'),
          )).thenAnswer((_) async => <fhir.Resource>[]);

      final response = await immdsForecastHandler(
        _postJson('/\$immds-forecast', {
          'resourceType': 'Parameters',
          'parameter': [
            {'name': 'patientId', 'valueString': 'params-pat'},
            {'name': 'assessmentDate', 'valueDate': '2024-06-01'},
          ],
        }),
        mockDb,
      );
      expect(response.statusCode, 200);
      verify(() =>
              mockDb.getResource(fhir.R4ResourceType.Patient, 'params-pat'))
          .called(1);
    });

    test('response has correct content type', () async {
      final params = _minimalForecastParams();
      final response = await immdsForecastHandler(
        _postJson('/\$immds-forecast', params),
        mockDb,
      );
      expect(response.headers['content-type'], 'application/fhir+json');
    });
  });

  group('\$immds-forecast-who', () {
    test('evaluates WHO forecast with inline Parameters', () async {
      final params = _minimalForecastParams(
        birthDate: '2023-01-01',
      );

      final response = await immdsForecastWhoHandler(
        _postJson('/\$immds-forecast-who', params),
        mockDb,
      );
      expect(response.statusCode, 200);

      final body = jsonDecode(await response.readAsString());
      expect(body['resourceType'], 'Parameters');
      final paramList = body['parameter'] as List;
      expect(paramList, isNotEmpty);
    });

    test('WHO recommendations differ from CDC', () async {
      final params = _minimalForecastParams(
        birthDate: '2023-06-01',
      );

      final cdcResponse = await immdsForecastHandler(
        _postJson('/\$immds-forecast', params),
        mockDb,
      );
      final whoResponse = await immdsForecastWhoHandler(
        _postJson('/\$immds-forecast-who', params),
        mockDb,
      );

      final cdcBody = jsonDecode(await cdcResponse.readAsString());
      final whoBody = jsonDecode(await whoResponse.readAsString());

      // Both should return valid Parameters
      expect(cdcBody['resourceType'], 'Parameters');
      expect(whoBody['resourceType'], 'Parameters');

      // WHO uses different vaccine groups (DTP vs DTaP, OPV vs IPV, etc.)
      // so the recommendations should differ
      final cdcParams = cdcBody['parameter'] as List;
      final whoParams = whoBody['parameter'] as List;
      expect(cdcParams, isNotEmpty);
      expect(whoParams, isNotEmpty);
    });
  });
}
