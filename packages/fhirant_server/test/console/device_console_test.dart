// Real Argon2id hashes at every sign-in and claim.
@Timeout(Duration(minutes: 4))
library;

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/fhirant_server.dart';
import 'package:fhirant_server/src/utils/smart_scopes.dart';
import 'package:test/test.dart';

/// The phone's own account screen does its work through [DeviceConsole]:
/// the server's routes, in process, with no port open (Grey 2026-11-21).
/// Each case here is something an administrator used to need the command
/// line for.
void main() {
  const adminName = 'admin-one';
  const adminPassword = 'Admin-own-pass-7q';
  const nursePassword = 'Nurse-own-pass-7q';

  late FhirAntDb db;
  late DeviceConsole console;
  late DeviceSession admin;

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
    final seeded = await AdminProvisioning.createInitialAdmin(
      db,
      adminName,
      adminPassword,
    );
    expect(seeded.status, AdminSetupStatus.created);
    console = DeviceConsole(
      db,
      jwtSecret: 'console-test-secret',
      breachedPasswords: null,
    );
    final signedIn = await console.signIn(adminName, adminPassword);
    expect(signedIn.ok, isTrue, reason: signedIn.refusal?.text);
    admin = signedIn.value!;
  });

  tearDown(() async {
    await console.close();
    await db.close();
  });

  Future<Account> account(String username) async {
    final list = await console.accounts(admin);
    expect(list.ok, isTrue, reason: list.refusal?.text);
    return list.value!.firstWhere((a) => a.username == username);
  }

  /// Creates nurse-a and goes through the owner's claim and the approval.
  Future<int> nurse() async {
    final created =
        await console.create(admin, username: 'nurse-a', role: 'clinician');
    expect(created.ok, isTrue, reason: created.refusal?.text);
    final id = (await account('nurse-a')).id;
    final code = await console.claim('nurse-a', nursePassword);
    expect(code.ok, isTrue, reason: code.refusal?.text);
    final approved = await console.approve(admin, id, code.value!);
    expect(approved.ok, isTrue, reason: approved.refusal?.text);
    return id;
  }

  test('works with no server started: sign in and list the accounts', () async {
    expect(admin.isAdmin, isTrue);
    final list = await console.accounts(admin);
    expect(list.value!.map((a) => a.username), [adminName]);
  });

  test('an account is created, waits, is claimed and approved by code',
      () async {
    await console.create(admin, username: 'nurse-a', role: 'clinician');
    final waiting = await account('nurse-a');
    expect(waiting.awaitingOwner, isTrue);
    expect(waiting.passwordSent, isFalse);
    final code = await console.claim('nurse-a', nursePassword);
    expect((await account('nurse-a')).passwordSent, isTrue);
    final wrong = await console.approve(admin, waiting.id, 'BCDFGHJK');
    expect(wrong.ok, isFalse);
    expect(wrong.refusal!.status, 400);
    // A wrong code drops what the owner sent: they send it again.
    final again = await console.claim('nurse-a', nursePassword);
    expect(code.value, isNot(again.value));
    expect((await console.approve(admin, waiting.id, again.value!)).ok, isTrue);
    expect((await account('nurse-a')).awaitingOwner, isFalse);
    final signedIn = await console.signIn('nurse-a', nursePassword);
    expect(signedIn.ok, isTrue);
    expect(signedIn.value!.isAdmin, isFalse);
    final refused = await console.accounts(signedIn.value!);
    expect(refused.refusal!.status, 403, reason: 'only an administrator');
  });

  test('reset, off and on, role and permissions', () async {
    final id = await nurse();
    expect((await console.reset(admin, id)).ok, isTrue);
    expect((await account('nurse-a')).awaitingOwner, isTrue);
    expect((await console.signIn('nurse-a', nursePassword)).ok, isFalse);
    final code = await console.claim('nurse-a', nursePassword);
    await console.approve(admin, id, code.value!);

    expect((await console.setActive(admin, id, active: false)).ok, isTrue);
    expect((await account('nurse-a')).active, isFalse);
    expect((await console.signIn('nurse-a', nursePassword)).ok, isFalse);
    expect((await console.setActive(admin, id, active: true)).ok, isTrue);
    expect((await console.signIn('nurse-a', nursePassword)).ok, isTrue);

    expect((await console.setRole(admin, id, 'readonly')).ok, isTrue);
    expect((await account('nurse-a')).role, 'readonly');
    expect(
      (await console.setScopes(admin, id, ['user/Patient.rs'])).ok,
      isTrue,
    );
    expect((await account('nurse-a')).scopes, ['user/Patient.rs']);
    expect((await console.setScopes(admin, id, null)).ok, isTrue);
    expect(
      (await account('nurse-a')).scopes,
      SmartScopeEnforcer.defaultScopesForRole('readonly'),
    );
  });

  test('the last administrator cannot be switched off or demoted', () async {
    final self = (await account(adminName)).id;
    final off = await console.setActive(admin, self, active: false);
    expect(off.refusal?.status, 409);
    final demoted = await console.setRole(admin, self, 'clinician');
    expect(demoted.refusal?.status, 409);
    expect((await console.reset(admin, self)).refusal?.status, 409);
    expect(off.refusal!.message, isNot(contains('/admin')));
  });

  test('a lockout after failed sign-ins is lifted by the administrator',
      () async {
    final id = await nurse();
    for (var i = 0; i < 5; i++) {
      await console.signIn('nurse-a', 'not-the-password');
    }
    expect((await account('nurse-a')).locked, isTrue);
    expect((await console.signIn('nurse-a', nursePassword)).ok, isFalse);
    expect((await console.unlock(admin, id)).ok, isTrue);
    expect((await console.signIn('nurse-a', nursePassword)).ok, isTrue);
  });

  test('the signed-in person changes their own password', () async {
    await nurse();
    final s = (await console.signIn('nurse-a', nursePassword)).value!;
    final changed =
        await console.changeOwnPassword(s, nursePassword, 'Nurse-new-pass-8r');
    expect(changed.ok, isTrue, reason: changed.refusal?.text);
    expect((await console.signIn('nurse-a', 'Nurse-new-pass-8r')).ok, isTrue);
    final weak = await console.changeOwnPassword(
      changed.value!,
      'Nurse-new-pass-8r',
      'short',
    );
    expect(weak.refusal?.status, 400);
  });

  test('signing out ends the session', () async {
    await console.signOut(admin);
    expect((await console.accounts(admin)).refusal?.status, 401);
  });

  test('every action is in the audit trail, from the device, by name',
      () async {
    final id = await nurse();
    await console.setRole(admin, id, 'readonly');
    await console.close();
    final events = (await db.search(
      resourceType: fhir.R4ResourceType.AuditEvent,
      count: 1000,
    ))
        .cast<fhir.AuditEvent>();
    final byAdmin = events.where(
      (e) => e.agent.any((a) => a.who?.display?.valueString == adminName),
    );
    // Six requests: the sign-in, the list, create, the claim, approve and
    // the role. Four carry the administrator's token: the sign-in carries
    // none and the claim is the owner's (measured 2026-11-22).
    expect(events, hasLength(6));
    expect(byAdmin, hasLength(4));
    for (final e in events) {
      expect(
        e.agent.first.network?.address?.valueString,
        DeviceConsole.deviceAddress,
      );
    }
  });

  test('register, change and remove an app (ASVS 5.0.0 V10.4.1)', () async {
    var put = await console.putApp(
      admin,
      'scarab',
      name: 'Scarab',
      redirectUris: ['https://scarab.example/cb'],
    );
    expect(put.ok, isTrue, reason: put.refusal?.text);
    var apps = (await console.apps(admin)).value!;
    expect(apps.single.clientId, 'scarab');
    expect(apps.single.redirectUris, ['https://scarab.example/cb']);

    put = await console.putApp(
      admin,
      'scarab',
      name: 'Scarab EHR',
      redirectUris: ['http://127.0.0.1/cb', 'https://scarab.example/cb'],
    );
    expect(put.ok, isTrue);
    apps = (await console.apps(admin)).value!;
    expect(apps.single.name, 'Scarab EHR');
    expect(apps.single.redirectUris, hasLength(2));

    final bad = await console.putApp(
      admin,
      'other',
      name: 'Other',
      redirectUris: ['javascript:alert(1)'],
    );
    expect(bad.ok, isFalse);
    expect(bad.refusal!.status, 400);

    // A client_id with characters a path must escape still reaches the
    // route whole.
    final spaced = await console.putApp(
      admin,
      'my app/v2',
      name: 'Spaced',
      redirectUris: ['https://spaced.example/cb'],
    );
    expect(spaced.ok, isTrue, reason: spaced.refusal?.text);
    expect(await db.getOAuthClient('my app/v2'), isNotNull);

    expect((await console.removeApp(admin, 'scarab')).ok, isTrue);
    expect((await console.removeApp(admin, 'my app/v2')).ok, isTrue);
    expect((await console.apps(admin)).value, isEmpty);
    final again = await console.removeApp(admin, 'scarab');
    expect(again.refusal?.status, 404);
  });

  test('the owner claim goes through the breach check', () async {
    final checked = DeviceConsole(
      db,
      jwtSecret: 'console-test-secret',
      breachedPasswords: (p) async => p == 'Summer2024!!',
    );
    await checked.create(admin, username: 'nurse-b', role: 'clinician');
    final r = await checked.claim('nurse-b', 'Summer2024!!');
    expect(r.refusal?.status, 400);
    expect(r.refusal!.message, PasswordPolicy.breachedMessage);
    await checked.close();
  });
}
