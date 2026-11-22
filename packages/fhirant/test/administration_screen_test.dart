import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant/src/screens/administration_screen.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/fhirant_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// The Administration section on the phone, against a real store and the
/// server's own routes (`DeviceConsole`): what an administrator used to need
/// the command line for (Grey 2026-11-21).
void main() {
  const adminName = 'admin-one';
  const adminPassword = 'Admin-own-pass-7q';
  const nursePassword = 'Nurse-own-pass-7q';

  late FhirAntDb db;
  late SyncJobs syncJobs;

  Future<DeviceConsole> open() async => DeviceConsole(
        db,
        jwtSecret: 'app-test-secret',
        syncJobs: syncJobs,
        breachedPasswords: null,
      );

  /// Real work (the store, Argon2) runs outside the test's fake clock; this
  /// lets it run and pumps until [found] appears.
  Future<void> until(WidgetTester tester, Finder found) async {
    for (var i = 0; i < 400; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      // Fake time moves too: the audit queue's tick and the messages'
      // timers run on it.
      await tester.pump(const Duration(milliseconds: 25));
      if (found.evaluate().isNotEmpty) return;
    }
    fail('never appeared: $found');
  }

  /// Closes the screen (it signs out) and lets what it queued finish,
  /// before the store closes.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    Duration idleLimit = const Duration(hours: 1),
  }) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: AdministrationScreen(openConsole: open, idleLimit: idleLimit),
      ),
    );
  }

  Future<void> signIn(WidgetTester tester, String name, String pw) async {
    await tester.enterText(find.byKey(const Key('sign-in-username')), name);
    await tester.enterText(find.byKey(const Key('sign-in-password')), pw);
    await tester.tap(find.byKey(const Key('sign-in')));
  }

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
    await AdminProvisioning.createInitialAdmin(db, adminName, adminPassword);
    syncJobs = SyncJobs();
  });

  tearDown(() => db.close());

  testWidgets('an administrator signs in and sees the accounts',
      (tester) async {
    await pumpScreen(tester);
    await signIn(tester, adminName, adminPassword);
    await until(tester, find.byKey(const Key('account-$adminName')));
    expect(find.text('Administrator'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a wrong password is refused with the sign-in answer',
      (tester) async {
    await pumpScreen(tester);
    await signIn(tester, adminName, 'not-the-password');
    await until(tester, find.text('Invalid username or password'));
    expect(find.byKey(const Key('new-account')), findsNothing);
    await finish(tester);
  });

  testWidgets(
      'create an account, the owner sets a password, the administrator '
      'approves it by code', (tester) async {
    await pumpScreen(tester);
    await signIn(tester, adminName, adminPassword);
    await until(tester, find.byKey(const Key('new-account')));

    await tester.tap(find.byKey(const Key('new-account')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-username')), 'nurse-a');
    await tester.tap(find.byKey(const Key('new-ok')));
    await until(tester, find.byKey(const Key('account-nurse-a')));
    expect(find.textContaining('waiting for its owner until'), findsOneWidget);

    // The owner, on the same phone.
    await tester.tap(find.byTooltip('Sign out'));
    await until(tester, find.byKey(const Key('set-my-password')));
    await tester.tap(find.byKey(const Key('set-my-password')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('fields-username')), 'nurse-a');
    await tester.enterText(find.byKey(const Key('fields-new')), nursePassword);
    await tester.enterText(
      find.byKey(const Key('fields-again')),
      nursePassword,
    );
    await tester.tap(find.byKey(const Key('fields-ok')));
    await until(tester, find.byKey(const Key('claim-code')));
    final code =
        (tester.widget(find.byKey(const Key('claim-code'))) as SelectableText)
            .data!;
    expect(code, matches(RegExp(r'^[A-Z]{4}-?[A-Z]{4}$')));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // The administrator approves.
    await signIn(tester, adminName, adminPassword);
    await until(tester, find.textContaining('waiting for your approval'));
    await tester.tap(find.byKey(const Key('account-nurse-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('action-approve')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ask-field')), code);
    await tester.tap(find.byKey(const Key('ask-ok')));
    await until(tester, find.text('Approved. nurse-a can sign in.'));

    // nurse-a signs in: not an administrator.
    await tester.tap(find.byTooltip('Sign out'));
    await until(tester, find.byKey(const Key('sign-in')));
    await signIn(tester, 'nurse-a', nursePassword);
    await until(tester, find.textContaining('Only an administrator'));
    await finish(tester);
  });

  testWidgets('switching off asks first, and the list says so', (tester) async {
    final console = await tester.runAsync(open);
    await tester.runAsync(() async {
      final s = (await console!.signIn(adminName, adminPassword)).value!;
      await console.create(s, username: 'nurse-b', role: 'clinician');
      await console.close();
    });
    await pumpScreen(tester);
    await signIn(tester, adminName, adminPassword);
    await until(tester, find.byKey(const Key('account-nurse-b')));
    await tester.tap(find.byKey(const Key('account-nurse-b')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('action-off')));
    await tester.pumpAndSettle();
    expect(find.text('Switch off nurse-b?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-ok')));
    await until(tester, find.textContaining('switched off'));
    await finish(tester);
  });

  testWidgets('the last administrator cannot switch itself off',
      (tester) async {
    await pumpScreen(tester);
    await signIn(tester, adminName, adminPassword);
    await until(tester, find.byKey(const Key('account-$adminName')));
    await tester.tap(find.byKey(const Key('account-$adminName')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('action-reset')), findsNothing);
    await tester.tap(find.byKey(const Key('action-off')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-ok')));
    await until(tester, find.byType(SnackBar));
    expect(find.textContaining('switched off.'), findsNothing);
    await finish(tester);
  });

  testWidgets(
      'sync with another fhirant server, signed in there with an account '
      'of its own', (tester) async {
    const peerName = 'peer-admin';
    const peerPassword = 'Peer-own-pass-7q';
    // The test binding answers every HTTP request with 400 and sends
    // nothing; the other server here is real, on the loopback address.
    final mocked = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = mocked);
    final peerDb = FhirAntDb(NativeDatabase.memory());
    final peer = FhirAntServer(
      peerDb,
      jwtSecret: 'peer-secret',
      breachedPasswords: null,
    );
    final socket = (await tester.runAsync(() async {
      await peerDb.initialize();
      await AdminProvisioning.createInitialAdmin(
        peerDb,
        peerName,
        peerPassword,
      );
      await peerDb.saveResource(
        fhir.Patient.fromJson({'resourceType': 'Patient', 'id': 'there'}),
      );
      await db.saveResource(
        fhir.Patient.fromJson({'resourceType': 'Patient', 'id': 'here'}),
      );
      return shelf_io.serve(
        peer.createHandler(peer.createRouter()),
        InternetAddress.loopbackIPv4,
        0,
      );
    }))!;
    final peerUrl = 'http://127.0.0.1:${socket.port}';
    addTearDown(() async {
      await socket.close(force: true);
      await peer.stop();
      await peerDb.close();
    });

    await pumpScreen(tester);
    await signIn(tester, adminName, adminPassword);
    await until(tester, find.byKey(const Key('tab-sync')));
    await tester.tap(find.byKey(const Key('tab-sync')));
    await until(tester, find.byKey(const Key('sync-none')));
    await tester.pumpAndSettle();

    // A wrong password there is that server's answer; this sign-in stays.
    await tester.tap(find.byKey(const Key('new-sync')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('sync-address')),
      'https://peer.example',
    );
    await tester.pump();
    expect(find.byKey(const Key('sync-unencrypted')), findsNothing);
    await tester.enterText(find.byKey(const Key('sync-address')), peerUrl);
    await tester.pump();
    expect(find.byKey(const Key('sync-unencrypted')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('sync-username')), peerName);
    await tester.enterText(find.byKey(const Key('sync-password')), 'wrong');
    await tester.tap(find.byKey(const Key('sync-ok')));
    await until(tester, find.textContaining('The other server: '));
    expect(find.byKey(const Key('tab-sync')), findsOneWidget);

    await tester.tap(find.byKey(const Key('new-sync')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('sync-address')), peerUrl);
    await tester.enterText(find.byKey(const Key('sync-username')), peerName);
    await tester.enterText(
      find.byKey(const Key('sync-password')),
      peerPassword,
    );
    await tester.tap(find.byKey(const Key('sync-ok')));
    await until(tester, find.byKey(const Key('sync-done')));
    expect(
      find.text('1 written to the other server, 1 written here.'),
      findsOneWidget,
    );
    expect(find.byKey(Key('peer-$peerUrl')), findsOneWidget);
    final both = await tester.runAsync(
      () async => [
        await db.getResource(fhir.R4ResourceType.Patient, 'there'),
        await peerDb.getResource(fhir.R4ResourceType.Patient, 'here'),
      ],
    );
    expect(both, everyElement(isNotNull));
    await finish(tester);
  });

  testWidgets(
      'register an app, change its addresses, remove it '
      '(ASVS 5.0.0 V10.4.1)', (tester) async {
    await pumpScreen(tester);
    await signIn(tester, adminName, adminPassword);
    await until(tester, find.byKey(const Key('tab-apps')));
    await tester.tap(find.byKey(const Key('tab-apps')));
    await until(tester, find.byKey(const Key('no-apps')));
    // The tab slides in; both tabs are built while it moves.
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('new-app')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('app-client-id')), 'scarab');
    await tester.enterText(find.byKey(const Key('app-name')), 'Scarab');
    await tester.enterText(
      find.byKey(const Key('app-addresses')),
      'https://scarab.example/cb\nhttp://127.0.0.1/cb',
    );
    await tester.tap(find.byKey(const Key('app-ok')));
    await until(tester, find.byKey(const Key('app-scarab')));
    var app = await tester.runAsync(() => db.getOAuthClient('scarab'));
    expect(app!.redirectUris, [
      'http://127.0.0.1/cb',
      'https://scarab.example/cb',
    ]);

    // A refused address is said, and nothing changes.
    await tester.tap(find.byKey(const Key('app-scarab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('app-change')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('app-addresses')),
      'javascript:alert(1)',
    );
    await tester.tap(find.byKey(const Key('app-ok')));
    await until(tester, find.textContaining('is not allowed'));
    app = await tester.runAsync(() => db.getOAuthClient('scarab'));
    expect(app!.redirectUris, hasLength(2));

    await tester.tap(find.byKey(const Key('app-scarab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('app-change')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('app-addresses')),
      'https://scarab.example/cb',
    );
    await tester.tap(find.byKey(const Key('app-ok')));
    await until(tester, find.text('scarab changed.'));
    app = await tester.runAsync(() => db.getOAuthClient('scarab'));
    expect(app!.redirectUris, ['https://scarab.example/cb']);

    await tester.tap(find.byKey(const Key('app-scarab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('app-remove')));
    await tester.pumpAndSettle();
    expect(find.text('Remove Scarab?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-ok')));
    await until(tester, find.byKey(const Key('no-apps')));
    expect(
      await tester.runAsync(() => db.getOAuthClient('scarab')),
      isNull,
    );
    await finish(tester);
  });

  testWidgets('leaving the app signs out', (tester) async {
    await pumpScreen(tester);
    await signIn(tester, adminName, adminPassword);
    await until(tester, find.byKey(const Key('new-account')));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await until(tester, find.byKey(const Key('ended-because')));
    expect(find.byKey(const Key('new-account')), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await finish(tester);
  });

  testWidgets('an idle session ends', (tester) async {
    await pumpScreen(tester, idleLimit: const Duration(milliseconds: 400));
    await signIn(tester, adminName, adminPassword);
    await until(tester, find.byKey(const Key('ended-because')));
    expect(
      find.text('Signed out after an hour without use.'),
      findsOneWidget,
    );
    await finish(tester);
  });
}
