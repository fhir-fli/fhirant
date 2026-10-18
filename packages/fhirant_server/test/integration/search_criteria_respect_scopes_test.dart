import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/auth/search_reach.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// R4B security.html 6.1.0.5.1 (hl7.org/fhir/R4B/security.html, read whole
/// 2026-10-17, verbatim): "A security implementation must consider whether
/// a client has the permission to access the resource being searched on,
/// as well as the chained resource(s)".
///
/// REVIEW-2026-10-17 finding 6, measured over HTTP: with
/// `user/Observation.rs` only, `Observation?subject:Patient.family=X`
/// answered 2 (a patient named X exists, and these are their results);
/// with `user/Patient.rs` only, `Patient?_has:Observation:subject:code=…`
/// answered which patients have that result; `If-None-Exist` with a chain
/// answered 412 or 201, the same question. Every route that takes a
/// client's criteria now refuses criteria that read a type the token may
/// not search.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String obsOnly;
  late String patOnly;
  late String clinician;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    obsOnly = await issueTestToken(
      db,
      username: 'obs-only',
      scopes: ['user/Observation.cruds'],
    );
    patOnly = await issueTestToken(
      db,
      username: 'pat-only',
      scopes: ['user/Patient.rs'],
    );
    clinician = await issueTestToken(
      db,
      username: 'clin',
      scopes: ['user/*.*'],
    );
    await db.saveResource(
      fhir.Patient(
        id: 'p1'.toFhirString,
        name: [fhir.HumanName(family: 'Secretname'.toFhirString)],
      ),
    );
    await db.saveResource(
      fhir.Observation(
        id: 'o1'.toFhirString,
        status: fhir.ObservationStatus.final_,
        code: fhir.CodeableConcept(text: 'hiv'.toFhirString),
        subject: fhir.Reference(reference: 'Patient/p1'.toFhirString),
      ),
    );
  });

  tearDown(() => db.close());

  Future<Response> call(
    String method,
    String path,
    String token, {
    Object? body,
    Map<String, String>? headers,
  }) async =>
      handler(
        testRequest(
          method,
          path,
          body: body == null
              ? null
              : body is String
                  ? body
                  : jsonEncode(body),
          headers: headers,
          authToken: token,
        ),
      );

  final observation = {
    'resourceType': 'Observation',
    'status': 'final',
    'code': {'text': 'x'},
  };

  group('a chain into a type the token may not search is 403', () {
    for (final (name, path) in [
      ('typed chain', '/Observation?subject:Patient.family=Secretname'),
      ('untyped chain', '/Observation?subject.family=Secretname'),
      (
        '_filter chain',
        '/Observation?_filter=subject.family%20eq%20Secretname'
      ),
    ]) {
      test(name, () async {
        final r = await call('GET', path, obsOnly);
        expect(r.statusCode, 403, reason: await r.readAsString());
      });
    }

    test('POST _search', () async {
      final r = await call(
        'POST',
        '/Observation/_search',
        obsOnly,
        body: 'subject:Patient.family=Secretname',
        headers: {'content-type': 'application/x-www-form-urlencoded'},
      );
      expect(r.statusCode, 403, reason: await r.readAsString());
    });

    test('_has on a type the token may not search', () async {
      final r = await call(
        'GET',
        '/Patient?_has:Observation:subject:code=hiv',
        patOnly,
      );
      expect(r.statusCode, 403, reason: await r.readAsString());
    });

    test('If-None-Exist', () async {
      final r = await call(
        'POST',
        '/Observation',
        obsOnly,
        body: observation,
        headers: {'If-None-Exist': 'subject:Patient.family=Secretname'},
      );
      expect(r.statusCode, 403, reason: await r.readAsString());
    });

    test('conditional update', () async {
      final r = await call(
        'PUT',
        '/Observation?subject:Patient.family=Secretname',
        obsOnly,
        body: observation,
      );
      expect(r.statusCode, 403, reason: await r.readAsString());
    });

    test('conditional delete', () async {
      final r = await call(
        'DELETE',
        '/Observation?subject:Patient.family=Secretname',
        obsOnly,
      );
      expect(r.statusCode, 403, reason: await r.readAsString());
      expect(
        await db.getResource(fhir.R4ResourceType.Observation, 'o1'),
        isNotNull,
      );
    });

    test('a batch GET entry', () async {
      final r = await call(
        'POST',
        '/',
        obsOnly,
        body: {
          'resourceType': 'Bundle',
          'type': 'batch',
          'entry': [
            {
              'request': {
                'method': 'GET',
                'url': 'Observation?subject:Patient.family=Secretname',
              },
            },
          ],
        },
      );
      final bundle = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
      final entry = (bundle['entry'] as List).single as Map<String, dynamic>;
      expect((entry['response'] as Map)['status'], startsWith('403'));
    });

    test('a transaction If-None-Exist entry', () async {
      final r = await call(
        'POST',
        '/',
        obsOnly,
        body: {
          'resourceType': 'Bundle',
          'type': 'transaction',
          'entry': [
            {
              'resource': observation,
              'request': {
                'method': 'POST',
                'url': 'Observation',
                'ifNoneExist': 'subject:Patient.family=Secretname',
              },
            },
          ],
        },
      );
      expect(r.statusCode, 403, reason: await r.readAsString());
    });

    test('Subscription criteria', () async {
      final r = await call(
        'POST',
        '/Subscription',
        obsOnly,
        body: {
          'resourceType': 'Subscription',
          'status': 'requested',
          'reason': 'x',
          'criteria': 'Observation?subject:Patient.family=Secretname',
          'channel': {'type': 'websocket'},
        },
      );
      // user/Observation.cruds does not cover Subscription either; the
      // refusal is required, whichever check makes it.
      expect(r.statusCode, 403, reason: await r.readAsString());
    });
  });

  test(
      'Subscription criteria that chain into an unsearchable type are kept '
      'in error', () async {
    final subs = await issueTestToken(
      db,
      username: 'subs',
      scopes: ['user/Observation.rs', 'user/Subscription.cruds'],
    );
    final r = await call(
      'POST',
      '/Subscription',
      subs,
      body: {
        'resourceType': 'Subscription',
        'status': 'requested',
        'reason': 'x',
        'criteria': 'Observation?subject:Patient.family=Secretname',
        'channel': {'type': 'websocket'},
      },
    );
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    expect(body['status'], 'error', reason: '$body');
    expect(body['error'], contains('Patient'));
  });

  test('an export _typeFilter that chains into an unsearchable type is 403',
      () async {
    await db.saveResource(
      fhir.FhirGroup(
        id: 'g1'.toFhirString,
        type: fhir.GroupType.person,
        actual: true.toFhirBoolean,
        member: [
          fhir.GroupMember(
            entity: fhir.Reference(reference: 'Patient/p1'.toFhirString),
          ),
        ],
      ),
    );
    final exporter = await issueTestToken(
      db,
      username: 'exporter',
      scopes: ['user/Group.rs', 'user/Observation.rs'],
    );
    final filter = Uri.encodeQueryComponent(
      'Observation?subject:Patient.family=Secretname',
    );
    final control = await call(
      'GET',
      r'/Group/g1/$export?_type=Observation',
      exporter,
      headers: {'Prefer': 'respond-async', 'Accept': 'application/fhir+json'},
    );
    expect(
      control.statusCode,
      202,
      reason: 'without the filter this token may start the export: '
          '${await control.readAsString()}',
    );
    final r = await call(
      'GET',
      '/Group/g1/\$export?_type=Observation&_typeFilter=$filter',
      exporter,
      headers: {'Prefer': 'respond-async', 'Accept': 'application/fhir+json'},
    );
    final text = await r.readAsString();
    expect(r.statusCode, 403, reason: text);
    expect(text, contains('chain'));
  });

  group('controls', () {
    test('a plain search on the granted type still works', () async {
      final r = await call('GET', '/Observation?code=hiv', obsOnly);
      expect(r.statusCode, 200);
    });

    test('a token that may search both types may chain', () async {
      final r = await call(
        'GET',
        '/Observation?subject:Patient.family=Secretname',
        clinician,
      );
      expect(r.statusCode, 200);
      final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
      expect(body['total'], 1);
    });

    test('typesReachedBy follows typed, untyped and nested reach', () {
      expect(
        typesReachedBy(db, 'Observation', {
          'subject:Patient.organization.name': ['x'],
        }),
        {'Patient', 'Organization'},
      );
      expect(
        typesReachedBy(db, 'Observation', {
          'subject.family': ['x'],
        }),
        {'Patient', 'Practitioner'},
        reason: 'R4B Observation-subject (4.3.0) targets nine types; Patient '
            'and Practitioner are the ones that define family',
      );
      expect(
        typesReachedBy(db, 'Patient', {
          '_has:Observation:subject:_has:Provenance:target:agent': ['x'],
        }),
        {'Observation', 'Provenance'},
      );
      expect(
        typesReachedBy(db, 'Observation', {
          'code': ['x'],
          'subject': ['Patient/p1'],
        }),
        isEmpty,
        reason: 'a plain reference value reads only the searched type',
      );
    });
  });
}
