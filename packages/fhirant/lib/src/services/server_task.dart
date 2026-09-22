import 'package:fhirant/src/config/security_config.dart';
import 'package:fhirant/src/services/database_service.dart';
import 'package:fhirant/src/services/server_service.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the user last left the server on: set by Start, cleared by Stop.
const serverWantedKey = 'server_wanted';

/// The port the server last ran on.
const serverPortKey = 'server_port';

/// The persisted auth posture (`ServerState` owns the choice).
const authDisabledKey = 'auth_disabled';

/// What the foreground service runs, in its own Dart engine, when it starts.
///
/// When the phone kills the app and Android restarts it, only the service
/// comes back: no screen, so none of the screen's code runs. Measured
/// 2026-09-21 on a OnePlus (tool/background_survival/RESULTS.md): OxygenOS
/// killed the app about 5 minutes after unplugging, Android restarted the
/// process 19 s later with the service up, and nothing served until someone
/// opened the app. This callback is the code that does run on that restart.
@pragma('vm:entry-point')
void serverTaskCallback() {
  FlutterForegroundTask.setTaskHandler(ServerTaskHandler());
}

/// Starts the server after Android restarted the service, if the user had
/// left it on. When the user starts the service (TaskStarter.developer) the
/// screen already runs the server, and this does nothing.
class ServerTaskHandler extends TaskHandler {
  DatabaseService? _db;
  ServerService? _server;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    if (starter != TaskStarter.system) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(serverWantedKey) ?? false)) {
        await FlutterForegroundTask.stopService();
        return;
      }
      final db = DatabaseService();
      await db.initialize();
      _db = db;
      final server = ServerService(db);
      await server.start(
        prefs.getInt(serverPortKey) ?? 8080,
        devMode: prefs.getBool(authDisabledKey) ?? kDefaultAuthDisabled,
      );
      _server = server;
      FhirantLogging().logInfo('Server restarted after the system restarted '
          'the service');
    } catch (e, stack) {
      FhirantLogging().logError(
        'Restarting the server after a system restart failed',
        e,
        stack,
      );
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    await _server?.stop();
    await _db?.close();
    _server = null;
    _db = null;
  }
}
