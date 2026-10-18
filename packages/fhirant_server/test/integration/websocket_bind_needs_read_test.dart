import 'dart:async';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

import 'test_helpers.dart';

/// REVIEW-2026-10-17 finding 11. `bind <id>` bound any id, so a socket of
/// one account received the pings of another's Subscription (measured over
/// HTTP 2026-10-17). REVIEW_DECISIONS.md, 2026-09-19 (A16.6): the bind
/// limits were reverted, binding an id that does not exist stays accepted,
/// and "the only exposure (binding another user's Subscription, no
/// ownership check)" was left unruled. FHIR defines no owner of a
/// Subscription, so the rule is the one every read uses: a socket binds a
/// stored Subscription only when its token may read that Subscription. An
/// id that is not stored binds as before.
void main() {
  late FhirAntDb db;
  late FhirAntServer server;
  late String clinician;
  late String patient;

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
    server = FhirAntServer(db, jwtSecret: testJwtSecret);
    await server.startHttp(0);
    clinician =
        await issueTestToken(db, username: 'clin', scopes: ['user/*.*']);
    patient = await issueTestToken(
      db,
      username: 'pat',
      scopes: ['patient/*.*'],
      patientId: 'p1',
    );
    await db.saveResource(
      fhir.Resource.fromJson({
        'resourceType': 'Subscription',
        'id': 's1',
        'status': 'active',
        'reason': 'x',
        'criteria': 'Observation?code:text=probe',
        'channel': {'type': 'websocket'},
      }),
    );
  });

  tearDown(() async {
    await server.stop();
    await db.close();
  });

  /// The server's first answer to `bind [id]` on a socket opened with
  /// [token], or null when there is none within two seconds.
  Future<String?> bind(String token, String id) async {
    final channel = IOWebSocketChannel.connect(
      Uri.parse('ws://127.0.0.1:${server.port}/ws'),
      headers: {'Authorization': 'Bearer $token'},
    );
    addTearDown(channel.sink.close);
    await channel.ready;
    channel.sink.add('bind $id');
    try {
      return await channel.stream
          .map((m) => m as String)
          .first
          .timeout(const Duration(seconds: 2));
    } on TimeoutException {
      return null;
    }
  }

  test('a token that may read the Subscription binds it', () async {
    expect(await bind(clinician, 's1'), 'bound s1');
  });

  test('a token that may not read the Subscription is not bound', () async {
    expect(await bind(patient, 's1'), isNull);
  });

  test('an id that is not stored still binds (A16.6 ruling)', () async {
    expect(await bind(patient, 'not-stored'), 'bound not-stored');
  });
}
