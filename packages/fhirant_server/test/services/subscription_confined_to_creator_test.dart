import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/auth/request_authorization.dart';
import 'package:fhirant_server/src/services/subscription_service.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../integration/test_helpers.dart';

/// R4B subscription.html, Security Considerations (read 2026-10-06,
/// verbatim): "The criteria are subject to the same limitations as the
/// client that created it, such as access to patient compartments etc."
///
/// REVIEW-2026-10-06 finding 3 (probe P11, `tool/review_2026-10-06/`): the
/// criteria ran against the whole store, so a token `patient/*.rs
/// user/Subscription.*` confined to pat1 created a websocket Subscription
/// on `Observation?subject=Patient/pat2&code=…` and received `ping` when
/// pat2's Observation was written, while its own search for pat2's
/// Observations answered total 0.
void main() {
  fhir.Subscription subscription({
    String criteria = 'Observation?code=http://loinc.org|718-7',
    List<Map<String, dynamic>>? extensions,
  }) =>
      fhir.Subscription.fromJson({
        'resourceType': 'Subscription',
        'id': 's1',
        'status': 'requested',
        'reason': 'test',
        'criteria': criteria,
        if (extensions != null) 'extension': extensions,
        'channel': {'type': 'websocket'},
      });

  fhir.Observation observation(String id, String patient) =>
      fhir.Observation.fromJson({
        'resourceType': 'Observation',
        'id': id,
        'status': 'final',
        'code': {
          'coding': [
            {'system': 'http://loinc.org', 'code': '718-7'},
          ],
        },
        'subject': {'reference': 'Patient/$patient'},
      });

  Principal confinedTo(String patient) => Principal(
        userId: 7,
        username: 'patu',
        role: 'readonly',
        scopes: ['patient/*.rs', 'user/Subscription.*'],
        patientId: patient,
      );

  group('SubscriptionService', () {
    late FhirAntDb db;
    late SubscriptionService service;

    setUp(() async {
      db = FhirAntDb(NativeDatabase.memory());
      service = SubscriptionService(db);
      await db.saveResource(fhir.Patient(id: fhir.FhirString('pat1')));
      await db.saveResource(fhir.Patient(id: fhir.FhirString('pat2')));
      await db.saveResource(observation('own', 'pat1'));
      await db.saveResource(observation('other', 'pat2'));
    });
    tearDown(() => db.close());

    test("the creator's compartment is recorded and the criteria run in it",
        () async {
      final stored =
          await service.activate(subscription(), principal: confinedTo('pat1'));
      expect(stored.status.valueString, 'active');
      expect(
        SubscriptionService.compartmentOf(stored)?.id,
        'pat1',
        reason: "the compartment is the server's statement on the resource",
      );
      expect(await service.matches(stored, observation('own', 'pat1')), isTrue);
      expect(
        await service.matches(stored, observation('other', 'pat2')),
        isFalse,
        reason: "another patient's matching Observation is not the creator's "
            'to see',
      );
    });

    test('an unconfined creator gets no compartment, and a forged one goes',
        () async {
      final forged = subscription(
        extensions: [
          {
            'url': SubscriptionService.compartmentExtensionUrl,
            'valueReference': {'reference': 'Patient/pat1'},
          },
        ],
      );
      final admin = Principal(
        userId: 1,
        username: 'adm',
        role: 'admin',
        scopes: ['system/*.*'],
      );
      for (final principal in [admin, null]) {
        final stored = await service.activate(forged, principal: principal);
        expect(SubscriptionService.compartmentOf(stored), isNull);
        expect(
          await service.matches(stored, observation('other', 'pat2')),
          isTrue,
        );
      }
    });

    test('a confined creator cannot widen it by sending another compartment',
        () async {
      final forged = subscription(
        extensions: [
          {
            'url': SubscriptionService.compartmentExtensionUrl,
            'valueReference': {'reference': 'Patient/pat2'},
          },
        ],
      );
      final stored =
          await service.activate(forged, principal: confinedTo('pat1'));
      expect(SubscriptionService.compartmentOf(stored)?.id, 'pat1');
    });
  });

  group('through the pipeline', () {
    late FhirAntDb db;
    late Handler handler;

    setUp(() async {
      final server = await createTestServer();
      db = server.db;
      handler = server.handler;
    });
    tearDown(() => db.close());

    test('a POST by a confined token stores the compartment', () async {
      final adm = await issueTestToken(
        db,
        username: 'adm',
        role: 'admin',
        scopes: ['system/*.*'],
      );
      final pat = await issueTestToken(
        db,
        username: 'patu',
        role: 'readonly',
        scopes: ['patient/*.rs', 'user/Subscription.*'],
        patientId: 'pat1',
      );
      for (final id in ['pat1', 'pat2']) {
        await handler(
          testRequest(
            'PUT',
            '/Patient/$id',
            body: jsonEncode({'resourceType': 'Patient', 'id': id}),
            authToken: adm,
          ),
        );
      }
      final created = await handler(
        testRequest(
          'POST',
          '/Subscription',
          body: jsonEncode(
            subscription(
              criteria: 'Observation?subject=Patient/pat2'
                  '&code=http://loinc.org|718-7',
            ).toJson(),
          ),
          authToken: pat,
        ),
      );
      expect(created.statusCode, 201);
      final body = jsonDecode(await created.readAsString()) as Map;
      final stored = (await db.getResource(
        fhir.R4ResourceType.Subscription,
        body['id'] as String,
      ))! as fhir.Subscription;
      expect(SubscriptionService.compartmentOf(stored)?.id, 'pat1');

      // The write the probe made: pat2's matching Observation. Not a match
      // for a subscription confined to pat1.
      await db.saveResource(observation('o-pat2', 'pat2'));
      final service = SubscriptionService(db);
      expect(
        await service.matches(stored, observation('o-pat2', 'pat2')),
        isFalse,
      );
    });
  });
}
