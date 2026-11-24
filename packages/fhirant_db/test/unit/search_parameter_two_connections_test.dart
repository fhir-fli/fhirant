import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:test/test.dart';

/// A search parameter uploaded through one connection to the store, then
/// searched through another. Two connections to one file stand for the
/// phone's foreground service (which serves requests after Android
/// restarted it) and the app's screens, each with its own FhirAntDb.
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

  Future<Object> search(FhirAntDb db) async {
    try {
      return (await db.fhirDao.search(
        resourceType: fhir.R4ResourceType.Patient,
        searchParameters: {
          'sex': ['female'],
        },
      ))
          .map((r) => r.id!.valueString)
          .toList();
    } on Object catch (e) {
      return 'threw ${e.runtimeType}: $e';
    }
  }

  test('probe', () async {
    for (final (id, gender) in [('f', 'female'), ('m', 'male')]) {
      await server.fhirDao.saveResource(
        fhir.Patient.fromJson({
          'resourceType': 'Patient',
          'id': id,
          'gender': gender,
        }),
      );
    }
    // The screen has searched once before the upload, so its copy of the
    // uploaded definitions is loaded.
    print('screen before upload: ${await search(screen)}');
    await server.fhirDao.saveResource(parameter);
    await server.rebuildSearchIndex();
    print('server after upload: ${await search(server)}');
    print('screen after upload: ${await search(screen)}');
    await screen.fhirDao.saveResource(
      fhir.Patient.fromJson({
        'resourceType': 'Patient',
        'id': 'f2',
        'gender': 'female',
      }),
    );
    print('server after screen saves f2: ${await search(server)}');
    final fresh = FhirAntDb(NativeDatabase(File('${dir.path}/fhirant.sqlite')));
    await fresh.initialize();
    print('new connection: ${await search(fresh)}');
    await fresh.close();
  });
}
