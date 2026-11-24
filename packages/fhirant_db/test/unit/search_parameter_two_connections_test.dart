import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:test/test.dart';

/// A search parameter uploaded through one connection to the store, then
/// searched and saved through another. Two connections to one file stand
/// for the phone's foreground service (which serves requests after Android
/// restarted it) and the app's screens (the Administration console's sync,
/// the sample data load), each with its own FhirAntDb.
///
/// Measured 2026-11-24 on fhir_db 0.15.4: the screens' connection answered
/// a search by the new code with every patient, and its own saves wrote no
/// rows under the code, until it was reopened. fhir_db 0.15.8 counts every
/// SearchParameter change in the file and each connection reads it.
void main() {
  late Directory dir;
  late FhirAntDb server;
  late FhirAntDb screen;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fhirant_db_sp_two_');
    final file = File('${dir.path}/fhirant.sqlite');
    server = FhirAntDb(NativeDatabase(file));
    await server.initialize();
    screen = FhirAntDb(NativeDatabase(file));
    await screen.initialize();
  });

  tearDown(() async {
    await server.searchParameterIndexing.idle;
    await screen.searchParameterIndexing.idle;
    await server.close();
    await screen.close();
    await dir.delete(recursive: true);
  });

  final parameter = fhir.SearchParameter.fromJson({
    'resourceType': 'SearchParameter',
    'id': 'sex',
    'url': 'http://example.org/SearchParameter/sex',
    'name': 'sex',
    'status': 'active',
    'description': 'test',
    'code': 'sex',
    'base': ['Patient'],
    'type': 'token',
    'expression': 'Patient.gender',
  });

  fhir.Patient patient(String id, String gender) => fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': id,
        'gender': gender,
      });

  Future<List<String>> females(FhirAntDb db) async => (await db.fhirDao.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'sex': ['female'],
        },
      ))
          .map((r) => r.id!.valueString!)
          .toList()
        ..sort();

  test(
      'an upload through the service is searched and indexed by the '
      'screens, and its earlier records are found without a re-index call',
      () async {
    await server.fhirDao.saveResources([
      patient('f', 'female'),
      patient('m', 'male'),
    ]);
    // The screens have read the uploaded parameters (none) already.
    expect(await females(screen), ['f', 'm']);

    await server.fhirDao.saveResource(parameter);
    await server.searchParameterIndexing.idle;
    expect(await females(server), ['f']);
    expect(await females(screen), ['f']);

    await screen.fhirDao.saveResource(patient('f2', 'female'));
    expect(await females(server), ['f', 'f2']);
  });
}
