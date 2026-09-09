import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/auth/admin_provisioning.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:fhirant_server/src/utils/password_hasher.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// The authorization findings of REVIEW-2026-09-08.md §1 as regression
/// tests. Each was first a probe that FAILED against the code
/// (`tool/review_2026-09-08/probes/OUTPUT.txt`); the expectation is the
/// specification's or the server's own security model, and the code was
/// changed to meet it. Two patients, one Observation each; p1's token is
/// patient-scoped to Patient/p1.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late Directory exportDir;

  setUp(() async {
    exportDir = await Directory.systemTemp.createTemp('authz-2026-09-08');
    final server = await createTestServer(exportDir: exportDir.path);
    db = server.db;
    handler = server.handler;
    await db.saveResource(
      fhir.Patient(
        id: 'p1'.toFhirString,
        name: [fhir.HumanName(family: 'One'.toFhirString)],
      ),
    );
    await db.saveResource(
      fhir.Patient(
        id: 'p2'.toFhirString,
        name: [fhir.HumanName(family: 'Two'.toFhirString)],
      ),
    );
    await db.saveResource(
      fhir.Observation(
        id: 'o1'.toFhirString,
        status: fhir.ObservationStatus.final_,
        code: fhir.CodeableConcept(text: 'weight'.toFhirString),
        subject: fhir.Reference(reference: 'Patient/p1'.toFhirString),
        hasMember: [
          fhir.Reference(reference: 'Observation/o2'.toFhirString),
        ],
      ),
    );
    await db.saveResource(
      fhir.Observation(
        id: 'o2'.toFhirString,
        status: fhir.ObservationStatus.final_,
        code: fhir.CodeableConcept(text: 'weight'.toFhirString),
        subject: fhir.Reference(reference: 'Patient/p2'.toFhirString),
      ),
    );
    await db.saveResource(
      fhir.Composition(
        id: 'c2'.toFhirString,
        status: fhir.CompositionStatus.final_,
        type: fhir.CodeableConcept(text: 'note'.toFhirString),
        date: fhir.FhirDateTime.fromString('2026-01-01'),
        author: [fhir.Reference(reference: 'Patient/p2'.toFhirString)],
        title: 'p2 note'.toFhirString,
        subject: fhir.Reference(reference: 'Patient/p2'.toFhirString),
      ),
    );
  });

  tearDown(() async {
    await db.close();
    await exportDir.delete(recursive: true);
  });

  Future<(int, String)> call(
    String method,
    String path, {
    String? body,
    String? token,
    Map<String, String>? headers,
  }) async {
    final r = await handler(
      testRequest(
        method,
        path,
        body: body,
        authToken: token,
        headers: {'content-type': 'application/fhir+json', ...?headers},
      ),
    );
    return (r.statusCode, await r.readAsString());
  }

  Future<String> p1Token([List<String>? scopes]) => issueTestToken(
        db,
        username: 'p1user',
        role: 'readonly',
        scopes: scopes ?? ['patient/*.cruds'],
        patientId: 'p1',
      );
  Future<String> clinician() =>
      issueTestToken(db, username: 'clin', scopes: ['user/*.cruds']);

  List<String> entryIds(String body) {
    final j = jsonDecode(body) as Map<String, dynamic>;
    return [
      for (final e in (j['entry'] as List? ?? const []))
        '${(e as Map)['resource']?['resourceType']}/${e['resource']?['id']}',
    ];
  }

  Map<String, dynamic> tx(
    List<Map<String, dynamic>> entries, {
    String type = 'transaction',
  }) =>
      {'resourceType': 'Bundle', 'type': type, 'entry': entries};

  group('row 1: the root path', () {
    test('POST / (transaction) without a token is refused', () async {
      final (s, b) = await call(
        'POST',
        '/',
        body: jsonEncode(
          tx([
            {
              'resource': {'resourceType': 'Patient', 'id': 'px'},
              'request': {'method': 'PUT', 'url': 'Patient/px'},
            }
          ]),
        ),
      );
      expect(s, 401, reason: b);
      expect(await db.getResource(fhir.R4ResourceType.Patient, 'px'), isNull);
    });
    test('GET /?_type=Patient (system search) without a token is refused',
        () async {
      final (s, b) = await call('GET', '/?_type=Patient');
      expect(s, 401, reason: b);
    });
    test('a bare GET / stays the welcome page', () async {
      final (s, _) = await call('GET', '/');
      expect(s, 200);
    });
    test('an authenticated transaction and system search still work', () async {
      final tok = await clinician();
      final (s1, b1) = await call('GET', '/?_type=Patient', token: tok);
      expect(s1, 200, reason: b1);
      expect(entryIds(b1), containsAll(['Patient/p1', 'Patient/p2']));
      final (s2, b2) = await call(
        'POST',
        '/',
        token: tok,
        body: jsonEncode(
          tx(
            [
              {
                'request': {'method': 'GET', 'url': 'Patient/p1'},
              }
            ],
            type: 'batch',
          ),
        ),
      );
      expect(s2, 200, reason: b2);
    });
  });

  group('row 19: middleware errors declare their content type', () {
    test('the 401 body is application/fhir+json', () async {
      final r = await handler(testRequest('GET', '/Patient'));
      expect(r.statusCode, 401);
      expect(r.headers['content-type'], 'application/fhir+json');
    });
  });

  group('row 3: the compartment is decided per type', () {
    test(
        'a mixed patient/ + user/ token keeps the compartment on the '
        'patient-scoped type', () async {
      final tok = await issueTestToken(
        db,
        username: 'mixed',
        role: 'readonly',
        scopes: ['patient/Observation.rs', 'user/Practitioner.rs'],
        patientId: 'p1',
      );
      final (s, b) = await call('GET', '/Observation', token: tok);
      expect(s, 200, reason: b);
      expect(entryIds(b), ['Observation/o1']);
    });
    test('and lifts it from the user-scoped type', () async {
      await db.saveResource(fhir.Practitioner(id: 'dr'.toFhirString));
      final tok = await issueTestToken(
        db,
        username: 'mixed',
        role: 'readonly',
        scopes: ['patient/Observation.rs', 'user/Practitioner.rs'],
        patientId: 'p1',
      );
      final (s, b) = await call('GET', '/Practitioner/dr', token: tok);
      expect(s, 200, reason: b);
    });
  });

  group('row 12: bulk export', () {
    test(r'Group/<id>/$export needs read on the exported types', () async {
      await db.saveResource(
        fhir.FhirGroup(
          id: 'g1'.toFhirString,
          type: fhir.GroupType.person,
          actual: fhir.FhirBoolean(true),
          member: [
            fhir.GroupMember(
              entity: fhir.Reference(reference: 'Patient/p2'.toFhirString),
            ),
          ],
        ),
      );
      final tok = await issueTestToken(
        db,
        username: 'grouponly',
        scopes: ['user/Group.r'],
      );
      final (s, b) = await call(
        'GET',
        r'/Group/g1/$export',
        token: tok,
        headers: {'prefer': 'respond-async'},
      );
      expect(s, 403, reason: b);
    });
    test('a patient-scoped token cannot run an export', () async {
      final (s, b) = await call(
        'GET',
        r'/Patient/$export',
        token: await p1Token(['patient/*.rs']),
        headers: {'prefer': 'respond-async'},
      );
      expect(s, 403, reason: b);
    });
  });

  group(r'row 7: Composition/$document', () {
    test("is confined to the token's patient compartment", () async {
      final (s, b) = await call(
        'GET',
        r'/Composition/c2/$document',
        token: await p1Token(['patient/*.rs']),
      );
      expect(s, 403, reason: b);
    });
    test('needs read on every type the document carries', () async {
      final tok = await issueTestToken(
        db,
        username: 'compo',
        scopes: ['user/Composition.rs'],
      );
      final (s, b) = await call(
        'GET',
        r'/Composition/c2/$document',
        token: tok,
      );
      expect(s, 403, reason: b);
      expect(b, contains('Patient'));
    });
  });

  group('row 5: system search', () {
    test('GET /?_type=Observation applies the compartment', () async {
      final (s, b) = await call(
        'GET',
        '/?_type=Observation',
        token: await p1Token(['patient/*.rs']),
      );
      expect(s, 200, reason: b);
      expect(entryIds(b), ['Observation/o1']);
    });
    test('POST /_search applies the compartment', () async {
      final (s, b) = await call(
        'POST',
        '/_search',
        token: await p1Token(['patient/*.rs']),
        body: '_type=Observation',
        headers: {'content-type': 'application/x-www-form-urlencoded'},
      );
      expect(s, 200, reason: b);
      expect(entryIds(b), ['Observation/o1']);
    });
    test('a type named in _type the token may not search is refused', () async {
      final tok = await issueTestToken(
        db,
        username: 'obsonly',
        scopes: ['user/Observation.rs'],
      );
      final (s, b) = await call('GET', '/?_type=Patient', token: tok);
      expect(s, 403, reason: b);
    });
    test('without _type the search runs over the types the token may search',
        () async {
      final tok = await issueTestToken(
        db,
        username: 'obsonly',
        scopes: ['user/Observation.rs'],
      );
      final (s, b) = await call('GET', '/?_id=p1,o1', token: tok);
      expect(s, 200, reason: b);
      expect(entryIds(b), ['Observation/o1']);
    });
  });

  group('rows 8, 9, 10, 11: conditional create, delete, includes, writes', () {
    test("If-None-Exist cannot match another patient's resource", () async {
      final body = jsonEncode({
        'resourceType': 'Observation',
        'status': 'final',
        'code': {'text': 'weight'},
        'subject': {'reference': 'Patient/p1'},
      });
      final (s, b) = await call(
        'POST',
        '/Observation',
        token: await p1Token(),
        body: body,
        headers: {'if-none-exist': '_id=o2'},
      );
      expect(s, 201, reason: b);
    });
    test('conditional DELETE stays inside the compartment', () async {
      final (s, _) = await call(
        'DELETE',
        '/Observation?status=final',
        token: await p1Token(),
      );
      expect(s, 204);
      expect(
        await db.getResource(fhir.R4ResourceType.Observation, 'o2'),
        isNotNull,
      );
      expect(
        await db.getResource(fhir.R4ResourceType.Observation, 'o1'),
        isNull,
      );
    });
    test("_include does not pull another patient's resource", () async {
      final (s, b) = await call(
        'GET',
        '/Observation?_include=Observation:has-member',
        token: await p1Token(['patient/*.rs']),
      );
      expect(s, 200, reason: b);
      expect(entryIds(b), ['Observation/o1']);
    });
    test('_include leaves out a type the token may not read', () async {
      final tok = await issueTestToken(
        db,
        username: 'obsonly',
        scopes: ['user/Observation.rs'],
      );
      final (s, b) = await call(
        'GET',
        '/Observation?_include=Observation:subject',
        token: tok,
      );
      expect(s, 200, reason: b);
      expect(entryIds(b), isNot(contains('Patient/p1')));
    });
    test('PUT cannot move a resource out of the compartment', () async {
      final body = jsonEncode({
        'resourceType': 'Observation',
        'id': 'o1',
        'status': 'final',
        'code': {'text': 'weight'},
        'subject': {'reference': 'Patient/p2'},
      });
      final (s, b) = await call(
        'PUT',
        '/Observation/o1',
        token: await p1Token(),
        body: body,
      );
      expect(s, 403, reason: b);
    });
    test('PATCH cannot move a resource out of the compartment', () async {
      final (s, b) = await call(
        'PATCH',
        '/Observation/o1',
        token: await p1Token(),
        body: jsonEncode([
          {
            'op': 'replace',
            'path': '/subject/reference',
            'value': 'Patient/p2',
          }
        ]),
        headers: {'content-type': 'application/json-patch+json'},
      );
      expect(s, 403, reason: b);
    });
  });

  group('row 2: every Bundle entry is authorized as its own request', () {
    test('a read-only patient token cannot write through a transaction',
        () async {
      final readOnly = await issueTestToken(
        db,
        username: 'readonly-patient',
        role: 'readonly',
        scopes: ['patient/Observation.rs'],
        patientId: 'p1',
      );
      final (s, b) = await call(
        'POST',
        '/',
        token: readOnly,
        body: jsonEncode(
          tx([
            {
              'resource': {
                'resourceType': 'Patient',
                'id': 'p2',
                'name': [
                  {'family': 'Overwritten'},
                ],
              },
              'request': {'method': 'PUT', 'url': 'Patient/p2'},
            }
          ]),
        ),
      );
      expect(s, 403, reason: b);
      final p2 = (await db.getResource(fhir.R4ResourceType.Patient, 'p2'))!
          as fhir.Patient;
      expect(p2.name?.first.family?.valueString, 'Two');
    });
    test("a batch GET of another patient's resource is refused per entry",
        () async {
      final (s, b) = await call(
        'POST',
        '/',
        token: await p1Token(['patient/*.rs']),
        body: jsonEncode(
          tx(
            [
              {
                'request': {'method': 'GET', 'url': 'Observation/o1'},
              },
              {
                'request': {'method': 'GET', 'url': 'Observation/o2'},
              },
            ],
            type: 'batch',
          ),
        ),
      );
      expect(s, 200, reason: b);
      final entries = (jsonDecode(b) as Map)['entry'] as List;
      expect(((entries[0] as Map)['response'] as Map)['status'], '200');
      expect(((entries[1] as Map)['response'] as Map)['status'], '403');
    });
    test('a transaction POST outside the compartment is rolled back', () async {
      final (s, b) = await call(
        'POST',
        '/',
        token: await p1Token(),
        body: jsonEncode(
          tx([
            {
              'resource': {
                'resourceType': 'Observation',
                'status': 'final',
                'code': {'text': 'x'},
                'subject': {'reference': 'Patient/p2'},
              },
              'request': {'method': 'POST', 'url': 'Observation'},
            }
          ]),
        ),
      );
      expect(s, 403, reason: b);
      expect(await db.getResourceCount(fhir.R4ResourceType.Observation), 2);
    });
  });

  group('row 4: history', () {
    test("instance history of another patient's resource is refused", () async {
      final (s, b) = await call(
        'GET',
        '/Observation/o2/_history',
        token: await p1Token(['patient/*.rs']),
      );
      expect(s, 403, reason: b);
    });
    test("vread of another patient's resource is refused", () async {
      final (s, b) = await call(
        'GET',
        '/Observation/o2/_history/1',
        token: await p1Token(['patient/*.rs']),
      );
      expect(s, 403, reason: b);
    });
    test('type history is confined to the compartment', () async {
      final (s, b) = await call(
        'GET',
        '/Observation/_history',
        token: await p1Token(['patient/*.rs']),
      );
      expect(s, 200, reason: b);
      expect(entryIds(b), ['Observation/o1']);
      expect((jsonDecode(b) as Map)['total'], 1);
    });
    test('system history is confined to the compartment', () async {
      final (s, b) = await call(
        'GET',
        '/_history',
        token: await p1Token(['patient/*.rs']),
      );
      expect(s, 200, reason: b);
      expect(entryIds(b), unorderedEquals(['Observation/o1', 'Patient/p1']));
    });
    test('system history needs a read on every type otherwise', () async {
      final tok = await issueTestToken(
        db,
        username: 'obsonly',
        scopes: ['user/Observation.rs'],
      );
      final (s, b) = await call('GET', '/_history', token: tok);
      expect(s, 403, reason: b);
      final (s2, b2) = await call('GET', '/_history', token: await clinician());
      expect(s2, 200, reason: b2);
      expect(entryIds(b2).length, 5);
    });
  });

  group(r'row 6: Library/$evaluate', () {
    final body = jsonEncode({
      'resourceType': 'Parameters',
      'parameter': [
        {
          'name': 'cql',
          'valueString': "library P version '1' using FHIR version '4.0.1' "
              'context Patient define Name: Patient.name.family',
        },
        {'name': 'subject', 'valueString': 'Patient/p2'},
      ],
    });
    test("inline CQL is confined to the token's patient", () async {
      final (s, b) = await call(
        'POST',
        r'/Library/$evaluate',
        token: await p1Token(['patient/*.rs']),
        body: body,
      );
      expect(s, 403, reason: b);
    });
    test('a narrow user scope cannot evaluate over a record', () async {
      final tok = await issueTestToken(
        db,
        username: 'libonly',
        scopes: ['user/Library.rs'],
      );
      final (s, b) = await call(
        'POST',
        r'/Library/$evaluate',
        token: tok,
        body: body,
      );
      expect(s, 403, reason: b);
    });
  });

  group('row 15: authorize errors', () {
    test(
        'an unsupported response_type is not redirected to an '
        'unregistered redirect_uri', () async {
      final r = await handler(
        testRequest(
          'POST',
          '/auth/authorize',
          body: 'response_type=token&client_id=evil'
              '&redirect_uri=https%3A%2F%2Fevil.example%2Fcb&state=x',
          headers: {'content-type': 'application/x-www-form-urlencoded'},
        ),
      );
      expect(r.statusCode, 400);
      expect(r.headers['location'], isNull);
    });
  });

  group('row 14: account state is re-read on every request', () {
    test("a deactivated account's live token stops working", () async {
      final tok = await issueTestToken(
        db,
        username: 'gone',
        scopes: ['user/*.cruds'],
      );
      expect((await call('GET', '/Patient/p1', token: tok)).$1, 200);
      final user = await db.getUserByUsername('gone');
      await db.deactivateUser(user!.id);
      final (s, _) = await call('GET', '/Patient/p1', token: tok);
      expect(s, 401);
    });
    test("a locked account's live token stops working", () async {
      final tok = await issueTestToken(
        db,
        username: 'locked',
        scopes: ['user/*.cruds'],
      );
      final user = await db.getUserByUsername('locked');
      await db.lockAccount(
        user!.id,
        DateTime.now().add(const Duration(minutes: 10)),
      );
      final (s, _) = await call('GET', '/Patient/p1', token: tok);
      expect(s, 401);
    });
  });

  group('row 13: Experimentation mode does not hand out the admin account', () {
    test('registration is refused while authentication is off', () async {
      final dev = FhirAntServer(db, jwtSecret: testJwtSecret, devMode: true);
      final devHandler = dev.createHandler(dev.createRouter());
      final r = await devHandler(
        testRequest(
          'POST',
          '/auth/register',
          body: jsonEncode({
            'username': 'stranger',
            'password': 'Stranger-pass-123',
          }),
          headers: {
            'content-type': 'application/json',
            'x-forwarded-for': '192.168.1.66',
          },
        ),
      );
      expect(r.statusCode, 403, reason: await r.readAsString());
      expect(await db.getUserCount(), 0);
    });
    test('provisioning asks for an admin, not for any user', () async {
      final salt = PasswordHasher.generateSalt();
      await db.createUser(
        username: 'nurse',
        passwordHash: PasswordHasher.hashPassword('nurse-password-123', salt),
        salt: salt,
      );
      expect(await AdminProvisioning.hasActiveAdmin(db), isFalse);
      final result = await AdminProvisioning.createInitialAdmin(
        db,
        'operator',
        'Operator-pass-123',
      );
      expect(result.status, AdminSetupStatus.created);
      expect(await AdminProvisioning.hasActiveAdmin(db), isTrue);
    });
  });
}
