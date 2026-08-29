import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:test/test.dart';

import 'test_helpers.dart';

/// Regression guard for finding F10 of SECURITY-REVIEW-2026-08-25.md.
///
/// ISO 27789 requires an audit record to identify the subject of care. The
/// trail used to record only the resource that was touched, so `GET
/// /Observation/123` named the Observation and never the patient — and "who
/// looked at this person's record", the question an audit trail exists to
/// answer, could not be answered for anything but a direct Patient read.
///
/// Run against a real database rather than a mock: what matters is the
/// AuditEvent that lands in the store, not that a method was called.
void main() {
  /// Waits for the fire-and-forget AuditEvent write to land.
  ///
  /// The middleware does not await the write, so the response returns before
  /// the event exists. A fixed sleep races: it passed locally and went red
  /// once in a full-suite run on a loaded machine. Poll for the expected
  /// count instead, and fail on the timeout rather than on a guess. Every
  /// caller wants at least one event, and asserts on its contents.
  Future<List<fhir.AuditEvent>> auditEvents(dynamic db) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    var events = <fhir.AuditEvent>[];
    while (DateTime.now().isBefore(deadline)) {
      final all =
          await db.getResourcesByType(fhir.R4ResourceType.AuditEvent) as List;
      events = all.whereType<fhir.AuditEvent>().toList();
      if (events.isNotEmpty) return events;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    return events;
  }

  /// The subjects of care named by the stored AuditEvents.
  ///
  /// Only entities carrying the Patient role count. A direct `GET /Patient/x`
  /// already puts `Patient/x` in the trail as the resource that was touched,
  /// so matching any Patient reference would let that case pass without the
  /// subject ever being resolved.
  Future<List<String>> auditedSubjects(dynamic db) async {
    final events = await auditEvents(db);
    final refs = <String>[];
    for (final e in events) {
      for (final entity in e.entity ?? <fhir.AuditEventEntity>[]) {
        if (entity.role?.code?.valueString != '1') continue;
        final r = entity.what?.reference?.valueString;
        if (r != null) refs.add(r);
      }
    }
    return refs;
  }

  test('reading an Observation audits the patient it belongs to', () async {
    final server = await createTestServer();
    final token = generateTestToken(scopes: ['user/*.cruds']);

    await server.db.saveResource(fhir.Patient(id: 'pat-1'.toFhirString));
    await server.db.saveResource(
      fhir.Observation(
        id: 'obs-1'.toFhirString,
        status: fhir.ObservationStatus.final_,
        code: fhir.CodeableConcept(text: 'weight'.toFhirString),
        subject: fhir.Reference(reference: 'Patient/pat-1'.toFhirString),
      ),
    );

    await server.handler(
      testRequest('GET', '/Observation/obs-1', authToken: token),
    );

    expect(
      await auditedSubjects(server.db),
      contains('Patient/pat-1'),
      reason: 'the audit trail must name whose record was read, not only '
          'which resource',
    );
  });

  test('reading a Patient names that patient once, not twice', () async {
    // The resource entity already is the subject here, so no second entity is
    // added: a duplicate would make the same access look like two.
    final server = await createTestServer();
    final token = generateTestToken(scopes: ['user/*.cruds']);
    await server.db.saveResource(fhir.Patient(id: 'pat-2'.toFhirString));

    await server.handler(
      testRequest('GET', '/Patient/pat-2', authToken: token),
    );

    final events = await auditEvents(server.db);
    final refs = events
        .expand((e) => e.entity ?? <fhir.AuditEventEntity>[])
        .map((en) => en.what?.reference?.valueString)
        .whereType<String>()
        .toList();

    expect(refs, equals(['Patient/pat-2']));
  });

  test('a resource that names no patient audits none, rather than a guess',
      () async {
    // Recording a patient who is merely mentioned would be worse than
    // recording nothing: it would answer "who accessed this person's record"
    // with a false positive, in a record kept for legal purposes.
    final server = await createTestServer();
    final token = generateTestToken(scopes: ['user/*.cruds']);
    await server.db.saveResource(
      fhir.Organization(
        id: 'org-1'.toFhirString,
        name: 'Camp Clinic'.toFhirString,
      ),
    );

    await server.handler(
      testRequest('GET', '/Organization/org-1', authToken: token),
    );

    expect(await auditedSubjects(server.db), isEmpty);
  });

  test(r'$fhirpath records the record it read, and its patient', () async {
    // The path is `/$fhirpath` for every call, so before this the trail could
    // say an expression ran but never against whose record. Combined with the
    // authorization gap in F1, that made it the sharpest hole in the server:
    // read any record, leave no trace.
    final server = await createTestServer();
    final token = generateTestToken(scopes: ['user/*.cruds']);

    await server.db.saveResource(fhir.Patient(id: 'pat-fp'.toFhirString));
    await server.db.saveResource(
      fhir.Observation(
        id: 'obs-fp'.toFhirString,
        status: fhir.ObservationStatus.final_,
        code: fhir.CodeableConcept(text: 'weight'.toFhirString),
        subject: fhir.Reference(reference: 'Patient/pat-fp'.toFhirString),
      ),
    );

    final response = await server.handler(
      testRequest(
        'GET',
        r'/$fhirpath?expression=Observation.status'
            '&resourceType=Observation&resourceId=obs-fp',
        authToken: token,
      ),
    );
    expect(response.statusCode, equals(200));

    final events = await auditEvents(server.db);
    final refs = events
        .expand((e) => e.entity ?? <fhir.AuditEventEntity>[])
        .map((en) => en.what?.reference?.valueString)
        .whereType<String>()
        .toList();

    expect(refs, contains('Observation/obs-fp'));
    expect(await auditedSubjects(server.db), contains('Patient/pat-fp'));
  });

  test(r'$fhirpath over a posted resource audits no record', () async {
    // The resource came from the caller and was never disclosed by the
    // server. Recording it would put a disclosure in the trail that did not
    // happen.
    final server = await createTestServer();
    final token = generateTestToken(scopes: ['user/*.cruds']);

    final response = await server.handler(
      testRequest(
        'POST',
        r'/$fhirpath?expression=Patient.id',
        body: '{"resourceType":"Patient","id":"posted-1"}',
        authToken: token,
      ),
    );
    expect(response.statusCode, equals(200));

    final events = await auditEvents(server.db);
    final refs = events
        .expand((e) => e.entity ?? <fhir.AuditEventEntity>[])
        .map((en) => en.what?.reference?.valueString)
        .whereType<String>()
        .toList();

    expect(refs, isEmpty);
  });

  test('the acting user is identified, not merely named', () async {
    // A display name is not an identifier. Two clinicians who share a name
    // must not be indistinguishable in a record kept for legal purposes.
    final server = await createTestServer();
    final token = generateTestToken(scopes: ['user/*.cruds']);
    await server.db.saveResource(fhir.Patient(id: 'pat-who'.toFhirString));

    await server.handler(
      testRequest('GET', '/Patient/pat-who', authToken: token),
    );

    final events = await auditEvents(server.db);
    final agents = events.expand((e) => e.agent).toList();

    expect(agents, isNotEmpty);
    final identifiers = agents
        .map((a) => a.who?.identifier)
        .whereType<fhir.Identifier>()
        .toList();
    expect(
      identifiers,
      isNotEmpty,
      reason: 'agent.who must carry an identifier for the account, not only '
          'a display name',
    );
    expect(
      identifiers.first.value?.valueString,
      isNotNull,
      reason: 'the identifier must carry the account id',
    );
    expect(identifiers.first.system?.valueString, equals('urn:fhirant:users'));
    // The human-readable name stays: it is what makes the record legible.
    expect(
      agents.map((a) => a.who?.display?.valueString).whereType<String>(),
      isNotEmpty,
    );
  });

  test('the requesting address is recorded', () async {
    // ATNA and ASTM E2147 both expect it, and it comes from the socket rather
    // than from a header the caller controls.
    final server = await createTestServer();
    final token = generateTestToken(scopes: ['user/*.cruds']);
    await server.db.saveResource(fhir.Patient(id: 'pat-3'.toFhirString));

    await server.handler(
      testRequest('GET', '/Patient/pat-3', authToken: token),
    );

    final events = await auditEvents(server.db);
    final addresses = events
        .expand((e) => e.agent)
        .map((a) => a.network?.address?.valueString)
        .whereType<String>()
        .toList();

    expect(addresses, isNotEmpty);
  });
}
