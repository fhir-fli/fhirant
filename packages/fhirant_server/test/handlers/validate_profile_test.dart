import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/validate_handler.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// `OperationDefinition/Resource-validate`, read from the packaged
/// specification rather than from memory:
///
/// > profile: If this is nominated, then the resource is validated against
/// > this specific profile. If a profile is nominated, and the server cannot
/// > validate against the nominated profile, it SHALL return an error.
///
/// Before this, `validate_handler.dart` never read `profile` at all, so a
/// client that nominated one was told its resource passed when only the base
/// type had been checked.
Future<void> main() async {
  late FhirAntDb db;

  const canonical = 'http://example.org/StructureDefinition/test-patient';

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    await db.saveResource(
      fhir.StructureDefinition.fromJson({
        'resourceType': 'StructureDefinition',
        'id': 'test-patient',
        'url': canonical,
        'version': '1.0.0',
        'name': 'TestPatient',
        'status': 'active',
        'kind': 'resource',
        'abstract': false,
        'type': 'Patient',
        'baseDefinition': 'http://hl7.org/fhir/StructureDefinition/Patient',
        'derivation': 'constraint',
        'snapshot': {
          'element': [
            {'id': 'Patient', 'path': 'Patient', 'min': 0, 'max': '*'},
            {
              'id': 'Patient.id',
              'path': 'Patient.id',
              'min': 0,
              'max': '1',
              'type': [
                {'code': 'http://hl7.org/fhirpath/System.String'},
              ],
            },
          ],
        },
      }),
    );
  });

  tearDown(() => db.close());

  Request post(String body, {String? query}) => Request(
        'POST',
        Uri.parse('http://localhost:8080/Patient/\$validate${query ?? ''}'),
        body: body,
      );

  const patient = '{"resourceType":"Patient","id":"p1"}';

  test('a nominated profile the server does not hold is refused', () async {
    final response = await validateHandler(
      post(patient, query: '?profile=http://example.org/nope'),
      db,
      'Patient',
    );

    expect(response.statusCode, 400);
    final outcome =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final issue = (outcome['issue'] as List).first as Map<String, dynamic>;
    expect(issue['code'], 'not-supported');
    expect(issue['diagnostics'], contains('http://example.org/nope'));
  });

  test('a nominated profile the server holds is used', () async {
    final response = await validateHandler(
      post(patient, query: '?profile=$canonical'),
      db,
      'Patient',
    );

    expect(response.statusCode, 200);
  });

  test('the version after | is matched', () async {
    final matching = await validateHandler(
      post(patient, query: '?profile=$canonical|1.0.0'),
      db,
      'Patient',
    );
    expect(matching.statusCode, 200);

    final wrongVersion = await validateHandler(
      post(patient, query: '?profile=$canonical|9.9.9'),
      db,
      'Patient',
    );
    expect(wrongVersion.statusCode, 400);
    final outcome =
        jsonDecode(await wrongVersion.readAsString()) as Map<String, dynamic>;
    expect(
      ((outcome['issue'] as List).first as Map<String, dynamic>)['code'],
      'not-supported',
    );
  });

  test('a Parameters body carries the resource and the profile', () async {
    final body = jsonEncode({
      'resourceType': 'Parameters',
      'parameter': [
        {
          'name': 'resource',
          'resource': {'resourceType': 'Patient', 'id': 'p1'},
        },
        {'name': 'profile', 'valueCanonical': canonical},
      ],
    });

    final response = await validateHandler(post(body), db, 'Patient');
    expect(response.statusCode, 200);
  });

  test('a Parameters body naming an unheld profile is refused', () async {
    final body = jsonEncode({
      'resourceType': 'Parameters',
      'parameter': [
        {
          'name': 'resource',
          'resource': {'resourceType': 'Patient', 'id': 'p1'},
        },
        {'name': 'profile', 'valueCanonical': 'http://example.org/nope'},
      ],
    });

    final response = await validateHandler(post(body), db, 'Patient');
    expect(response.statusCode, 400);
  });

  test('a Parameters body with no resource is refused', () async {
    final body = jsonEncode({
      'resourceType': 'Parameters',
      'parameter': [
        {'name': 'profile', 'valueCanonical': canonical},
      ],
    });

    final response = await validateHandler(post(body), db, 'Patient');
    expect(response.statusCode, 400);
    final outcome =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(
      ((outcome['issue'] as List).first as Map<String, dynamic>)['diagnostics'],
      contains('resource'),
    );
  });

  test('the base type is resolved from this server, then a binding is not',
      () async {
    // Two things at once, because that is the honest state today.
    //
    // The base definition IS found now: the handler looks up
    // http://hl7.org/fhir/StructureDefinition/Patient in this server's own
    // store, which spec_loader fills from profiles-resources.ndjson. Before
    // that, every call answered "No StructureDefinition found for
    // resourceType: Patient" and nothing was ever validated.
    //
    // Validation then stops at the first coded element, because the engine
    // resolves value sets through an empty in-memory cache it builds itself
    // and fhir_r4_validation 0.9.0 gives a caller no way to supply one. That
    // throws, and the handler reports 422 naming what it could not resolve
    // rather than a 500. The seam is in the package now; when that release
    // lands this becomes a 200.
    await db.saveResource(_packagedPatientDefinition());

    final response = await validateHandler(post(patient), db, 'Patient');
    expect(response.statusCode, 422);

    final outcome =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final issue = (outcome['issue'] as List).first as Map<String, dynamic>;
    expect(issue['code'], 'not-supported');
    expect(issue['diagnostics'], contains('Resource not found at'));
    expect(
      issue['diagnostics'],
      isNot(contains('No StructureDefinition found')),
    );
  });

  test('without the base definition, the engine says so', () async {
    // Kept deliberately: this is what every $validate call used to return,
    // and it is the honest answer when the specification has not been loaded.
    final response = await validateHandler(post(patient), db, 'Patient');
    expect(response.statusCode, 400);
    final outcome =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(
      ((outcome['issue'] as List).first as Map<String, dynamic>)['diagnostics'],
      contains('No StructureDefinition found'),
    );
  });

  test('with the value sets loaded too, validation completes', () async {
    // The point of the resourceCache seam: every canonical the engine needs
    // comes from this server's own store, offline. Loading the base
    // definition alone leaves it stopping at the first coded element, which
    // the test above pins; loading the packaged value sets as well lets it
    // finish. spec_loader.dart does exactly this on first boot.
    await db.saveResource(_packagedPatientDefinition());
    for (final valueSet in _packagedValueSets()) {
      await db.saveResource(valueSet);
    }

    final response = await validateHandler(post(patient), db, 'Patient');
    expect(response.statusCode, 200);

    final outcome =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final diagnostics = ((outcome['issue'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((i) => i['diagnostics'])
        .toList();
    expect(diagnostics, isNot(contains(contains('Resource not found at'))));
    expect(
      diagnostics,
      isNot(contains(contains('No StructureDefinition found'))),
    );
  });

  test('the resource type in the body must still match the path', () async {
    final response = await validateHandler(
      post('{"resourceType":"Observation","status":"final"}'),
      db,
      'Patient',
    );
    expect(response.statusCode, 400);
  });
}

/// The Patient StructureDefinition as published, read from the packaged
/// specification rather than hand-written, so this test cannot pass against a
/// definition shaped to suit it.
fhir.StructureDefinition _packagedPatientDefinition() {
  final file = File('assets/fhir_spec/profiles-resources.ndjson');
  for (final line in file.readAsLinesSync()) {
    if (!line.contains('"id":"Patient"')) continue;
    final json = jsonDecode(line) as Map<String, dynamic>;
    if (json['resourceType'] == 'StructureDefinition' &&
        json['id'] == 'Patient') {
      return fhir.StructureDefinition.fromJson(json);
    }
  }
  throw StateError('Patient StructureDefinition not found in the spec assets');
}

/// The packaged value sets a Patient's coded elements are bound to.
///
/// Read from the shipped specification rather than hand-written, and limited
/// to the ones this test needs so the in-memory database stays small.
List<fhir.ValueSet> _packagedValueSets() {
  const wanted = {
    'http://hl7.org/fhir/ValueSet/languages',
    'http://hl7.org/fhir/ValueSet/administrative-gender',
    'http://hl7.org/fhir/ValueSet/marital-status',
    'http://hl7.org/fhir/ValueSet/link-type',
    'http://hl7.org/fhir/ValueSet/name-use',
    'http://hl7.org/fhir/ValueSet/contact-point-system',
    'http://hl7.org/fhir/ValueSet/contact-point-use',
    'http://hl7.org/fhir/ValueSet/address-use',
    'http://hl7.org/fhir/ValueSet/address-type',
    'http://hl7.org/fhir/ValueSet/identifier-use',
    'http://hl7.org/fhir/ValueSet/patient-contactrelationship',
    'http://hl7.org/fhir/ValueSet/narrative-status',
  };
  final found = <fhir.ValueSet>[];
  for (final line
      in File('assets/fhir_spec/valuesets.ndjson').readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final json = jsonDecode(line) as Map<String, dynamic>;
    if (json['resourceType'] == 'ValueSet' && wanted.contains(json['url'])) {
      found.add(fhir.ValueSet.fromJson(json));
    }
  }
  return found;
}
