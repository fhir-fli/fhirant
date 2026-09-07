import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// `FhirAntServer.baseUrl` reaches the store as `FhirDao.serverBaseUrl`.
///
/// R4B search.html 3.1.1.4.12 (quoted in fhir_r4_db's FhirDao): "A relative
/// reference resolving to the same value as a specified absolute URL, or vice
/// versa, qualifies as a match". With the base known, `subject=Patient/p1`
/// finds a stored `<base>/Patient/p1` and not another server's `Patient/p1`.
void main() {
  Future<({FhirAntDb db, FhirAntServer server})> serverWith(
    String? baseUrl,
  ) async {
    final db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
    final server = FhirAntServer(
      db,
      jwtSecret: testJwtSecret,
      baseUrl: baseUrl,
    );
    return (db: db, server: server);
  }

  Map<String, dynamic> observation(String id, String subject) => {
        'resourceType': 'Observation',
        'id': id,
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '8867-4'},
          ],
        },
        'subject': {'reference': subject},
      };

  test('the constructor and the setter reach the store', () async {
    final s = await serverWith('https://10.0.0.5:8080');
    expect(s.db.fhirDao.serverBaseUrl, 'https://10.0.0.5:8080');
    s.server.baseUrl = ' https://10.0.0.6:8080 ';
    expect(s.db.fhirDao.serverBaseUrl, 'https://10.0.0.6:8080');
    s.server.baseUrl = '';
    expect(s.db.fhirDao.serverBaseUrl, isNull);
    await s.db.close();
  });

  test(
      'with the base known, a relative search finds our absolute reference '
      "and not another server's", () async {
    final s = await serverWith('https://10.0.0.5:8080');
    await s.db.saveResource(
      fhir.Observation.fromJson(
        observation('ours', 'https://10.0.0.5:8080/Patient/p1'),
      ),
    );
    await s.db.saveResource(
      fhir.Observation.fromJson(
        observation('theirs', 'https://other.example.org/fhir/Patient/p1'),
      ),
    );
    await s.db.saveResource(
      fhir.Observation.fromJson(observation('relative', 'Patient/p1')),
    );
    final handler = s.server.createHandler(s.server.createRouter());
    final response = await handler(
      testRequest(
        'GET',
        '/Observation?subject=Patient/p1',
        authToken: generateTestToken(scopes: ['user/*.cruds']),
      ),
    );
    expect(response.statusCode, 200);
    final body =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final ids = (body['entry'] as List)
        .map((e) => e['resource']['id'] as String)
        .toList()
      ..sort();
    expect(ids, ['ours', 'relative']);
    await s.db.close();
  });
}
