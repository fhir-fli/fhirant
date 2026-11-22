import 'dart:async';

import 'package:fhirant_server/fhirant_server.dart'
    show ConsoleResult, DeviceConsole, DeviceSession;
import 'package:flutter/widgets.dart';

/// Who is signed in to the Administration section on this phone, and for
/// how long.
///
/// The app never asks who holds the phone, so the section starts with a
/// sign-in through the server's own route (the lockout and the audit apply,
/// `DeviceConsole`). The session is held in memory only and ends:
///
/// - when the app leaves the foreground (the phone locked, put down, or
///   another app opened) or the section is closed;
/// - after [idleLimit] with no use: NIST SP 800-63B-4, AAL2 reauthentication
///   (read 2026-11-21): "The inactivity timeout SHOULD be no more than 1
///   hour";
/// - at the latest when the server's 8-hour access token runs out, which the
///   server enforces (a refused call signs the person out here).
///
/// Ending it signs out on the server too: both tokens are revoked.
class AdminSession extends ChangeNotifier with WidgetsBindingObserver {
  AdminSession(
    this._openConsole, {
    this.idleLimit = const Duration(hours: 1),
  }) {
    WidgetsBinding.instance.addObserver(this);
  }

  final Future<DeviceConsole> Function() _openConsole;
  final Duration idleLimit;

  DeviceConsole? _console;
  DeviceSession? _session;
  Timer? _idle;
  bool _disposed = false;

  /// Why the last session ended, for the sign-in screen; null after a
  /// sign-out the person asked for.
  String? endedBecause;

  DeviceSession? get session => _session;
  bool get signedIn => _session != null;

  Future<DeviceConsole> console() async => _console ??= await _openConsole();

  Future<ConsoleResult<DeviceSession>> signIn(
    String username,
    String password,
  ) async {
    final result = await (await console()).signIn(username, password);
    if (result.ok) {
      _session = result.value;
      endedBecause = null;
      touch();
      notifyListeners();
    }
    return result;
  }

  /// Replaces the session after a password change handed back a new one.
  void replace(DeviceSession session) {
    _session = session;
    touch();
    notifyListeners();
  }

  /// Marks the section as in use: the idle limit starts again.
  void touch() {
    _idle?.cancel();
    if (_session == null) return;
    _idle = Timer(
      idleLimit,
      () => unawaited(end('Signed out after an hour without use.')),
    );
  }

  /// Ends the session, here and on the server.
  Future<void> end([String? reason]) async {
    _idle?.cancel();
    final session = _session;
    _session = null;
    endedBecause = reason;
    if (!_disposed) notifyListeners();
    final console = _console;
    if (session != null && console != null) {
      await console.signOut(session);
      await console.close();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Paused or hidden: the app is no longer what the person sees. Not
    // `inactive`, which a dialog or the notification shade also causes.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_session != null) {
        unawaited(end('Signed out when the app left the screen.'));
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(end());
    super.dispose();
  }
}
