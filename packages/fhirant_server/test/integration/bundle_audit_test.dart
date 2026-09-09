import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-06 finding 15: a Bundle used to be audited as one
/// `POST /` event, action C, no entity, no subject of care, however many
/// patients its entries touched. Now the envelope is recorded as the
/// `transaction`/`batch` interaction and every entry as an event of its own
/// with its record, status and patient. Asserted on the AuditEvents that
/// land in the store.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    token = await issueTestToken(
      db,
      username: 'bundle-auditor',
      role: 'admin',
      scopes: ['system/*.*'],
    );
  });

  tearDown(() => db.close());

  /// Waits for at least [atLeast] events to land (the write is queued).
  Future<List<fhir.AuditEvent>> auditEvents({required int atLeast}) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    var events = <fhir.AuditEvent>[];
    while (DateTime.now().isBefore(deadline)) {
      final all = await db.getResourcesByType(fhir.R4ResourceType.AuditEvent);
      events = all.whereType<fhir.AuditEvent>().toList();
      if (events.length >= atLeast) return events;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    return events;
  }

  Future<Response> postBundle(Map<String, dynamic> bundle) async => handler(
        testRequest(
          'POST',
          '/',
          body: jsonEncode(bundle),
          headers: {'content-type': 'application/fhir+json'},
          authToken: token,
        ),
      );

  ({
    String? action,
    String? subtype,
    List<String> entities,
    List<String> patients
  }) shape(fhir.AuditEvent e) => (
        action: e.action?.valueString,
        subtype: e.subtype?.first.code?.valueString,
        entities: [
          for (final en in e.entity ?? const <fhir.AuditEventEntity>[])
            if (en.role == null) en.what?.reference?.valueString ?? '',
        ],
        patients: [
          for (final en in e.entity ?? const <fhir.AuditEventEntity>[])
            if (en.role?.code?.valueString == '1')
              en.what?.reference?.valueString ?? '',
        ],
      );

  Map<String, dynamic> observation(String id, String patient) => {
        'resourceType': 'Observation',
        'id': id,
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '8480-6'},
          ],
        },
        'subject': {'reference': 'Patient/$patient'},
      };

  test(
      'a transaction touching three patients leaves three patients in the '
      'trail, one event per entry, plus the transaction itself', () async {
    await db.saveResource(fhir.Patient(id: 'p-a'.toFhirString));
    await db.saveResource(fhir.Patient(id: 'p-b'.toFhirString));
    await db.saveResource(fhir.Patient(id: 'p-c'.toFhirString));
    await db.saveResource(
      fhir.Observation.fromJson(observation('obs-c', 'p-c')),
    );

    final r = await postBundle({
      'resourceType': 'Bundle',
      'type': 'transaction',
      'entry': [
        {
          'resource': observation('ignored', 'p-a'),
          'request': {'method': 'POST', 'url': 'Observation'},
        },
        {
          'resource': observation('obs-b', 'p-b'),
          'request': {'method': 'PUT', 'url': 'Observation/obs-b'},
        },
        {
          'request': {'method': 'DELETE', 'url': 'Observation/obs-c'},
        },
        {
          'request': {'method': 'GET', 'url': 'Patient/p-a'},
        },
      ],
    });
    expect(r.statusCode, 200, reason: await r.readAsString());

    final events = await auditEvents(atLeast: 5);
    expect(events, hasLength(5));
    final shapes = events.map(shape).toList();

    // The envelope: the transaction interaction, not a create of nothing.
    final envelope = shapes.where((s) => s.subtype == 'transaction').toList();
    expect(envelope, hasLength(1));
    expect(envelope.single.action, 'E');
    expect(envelope.single.entities, isEmpty);

    // One event per entry, each with its own record and patient.
    final create = shapes.singleWhere((s) => s.subtype == 'create');
    expect(create.action, 'C');
    expect(create.entities.single, startsWith('Observation/'));
    expect(create.entities.single, isNot('Observation/ignored'));
    expect(create.patients, ['Patient/p-a']);

    final update = shapes.singleWhere((s) => s.subtype == 'update');
    expect(update.action, 'U');
    expect(update.entities, ['Observation/obs-b']);
    expect(update.patients, ['Patient/p-b']);

    // The deleted resource's subject was read before the delete.
    final delete = shapes.singleWhere((s) => s.subtype == 'delete');
    expect(delete.action, 'D');
    expect(delete.entities, ['Observation/obs-c']);
    expect(delete.patients, ['Patient/p-c']);

    final read = shapes.singleWhere((s) => s.subtype == 'read');
    expect(read.action, 'R');
    expect(read.entities, ['Patient/p-a']);
    expect(read.patients, isEmpty, reason: 'the entity is the patient');

    expect(
      shapes.expand((s) => s.patients).toSet(),
      {'Patient/p-a', 'Patient/p-b', 'Patient/p-c'},
    );
    for (final e in events) {
      expect(e.outcome?.valueString, '0');
    }
  });

  test('a batch records each entry with its own outcome', () async {
    await db.saveResource(fhir.Patient(id: 'p-d'.toFhirString));
    final r = await postBundle({
      'resourceType': 'Bundle',
      'type': 'batch',
      'entry': [
        {
          'request': {'method': 'GET', 'url': 'Patient/p-d'},
        },
        {
          'request': {'method': 'GET', 'url': 'Patient/nobody'},
        },
        {
          'request': {'method': 'GET', 'url': 'Patient?name=x'},
        },
      ],
    });
    expect(r.statusCode, 200, reason: await r.readAsString());

    final events = await auditEvents(atLeast: 4);
    expect(events, hasLength(4));
    final shapes = events.map(shape).toList();
    expect(
      shapes.where((s) => s.subtype == 'batch').single.action,
      'E',
    );
    final reads = events.where((e) => shape(e).subtype == 'read').toList();
    expect(reads, hasLength(2));
    final byEntity = {
      for (final e in reads) shape(e).entities.single: e.outcome?.valueString,
    };
    expect(byEntity, {'Patient/p-d': '0', 'Patient/nobody': '4'});
    // The type-level GET is the search interaction, with no single record.
    final search = shapes.singleWhere((s) => s.subtype == 'search');
    expect(search.action, 'R');
    expect(search.entities, isEmpty);
  });

  test(
      'a rolled-back transaction records every entry as failed, and the '
      'envelope with it', () async {
    final r = await postBundle({
      'resourceType': 'Bundle',
      'type': 'transaction',
      'entry': [
        {
          'resource': {'resourceType': 'Patient', 'id': 'p-e'},
          'request': {'method': 'PUT', 'url': 'Patient/p-e'},
        },
        {
          'request': {'method': 'DELETE', 'url': 'Patient/never-there'},
        },
      ],
    });
    expect(r.statusCode, 404, reason: await r.readAsString());
    expect(await db.getResource(fhir.R4ResourceType.Patient, 'p-e'), isNull);

    final events = await auditEvents(atLeast: 3);
    expect(events, hasLength(3));
    for (final e in events) {
      expect(e.outcome?.valueString, '4', reason: 'nothing was written');
    }
    final shapes = events.map(shape).toList();
    expect(shapes.singleWhere((s) => s.subtype == 'update').entities, [
      'Patient/p-e',
    ]);
    expect(shapes.singleWhere((s) => s.subtype == 'delete').entities, [
      'Patient/never-there',
    ]);
  });
}
