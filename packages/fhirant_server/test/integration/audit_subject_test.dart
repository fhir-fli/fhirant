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
  /// The subjects of care named by the stored AuditEvents.
  ///
  /// Only entities carrying the Patient role count. A direct `GET /Patient/x`
  /// already puts `Patient/x` in the trail as the resource that was touched,
  /// so matching any Patient reference would let that case pass without the
  /// subject ever being resolved.
  Future<List<String>> auditedSubjects(dynamic db) async {
    final events =
        await db.getResourcesByType(fhir.R4ResourceType.AuditEvent) as List;
    final refs = <String>[];
    for (final e in events.whereType<fhir.AuditEvent>()) {
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
    // The AuditEvent is written fire-and-forget so the response is not delayed.
    await Future<void>.delayed(const Duration(milliseconds: 200));

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
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final events = await server.db
        .getResourcesByType(fhir.R4ResourceType.AuditEvent) as List;
    final refs = events
        .whereType<fhir.AuditEvent>()
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
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(await auditedSubjects(server.db), isEmpty);
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
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final events = await server.db
        .getResourcesByType(fhir.R4ResourceType.AuditEvent) as List;
    final addresses = events
        .whereType<fhir.AuditEvent>()
        .expand((e) => e.agent)
        .map((a) => a.network?.address?.valueString)
        .whereType<String>()
        .toList();

    expect(addresses, isNotEmpty);
  });
}
