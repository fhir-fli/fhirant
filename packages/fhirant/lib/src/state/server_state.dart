import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' show R4ResourceType;
import 'package:fhirant/src/config/security_config.dart';
import 'package:fhirant/src/services/database_service.dart';
import 'package:fhirant/src/services/server_service.dart';
import 'package:fhirant_db/fhirant_db.dart' show FhirAntDb;
import 'package:fhirant_server/fhirant_server.dart' show RequestLogEntry;
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ServerStatus { stopped, starting, running, stopping, error }

class ServerState extends ChangeNotifier {
  ServerState({
    required DatabaseService dbService,
    required ServerService serverService,
  })  : _dbService = dbService,
        _serverService = serverService {
    unawaited(_detectWifiIp());
    unawaited(_loadPersistedMode());
  }
  final DatabaseService _dbService;
  final ServerService _serverService;

  /// SharedPreferences key for the persisted auth posture. Absent until the
  /// operator has explicitly chosen a mode.
  static const _authDisabledKey = 'auth_disabled';

  ServerStatus _status = ServerStatus.stopped;
  String? _errorMessage;
  String? _wifiIp;
  int _port = 8080;

  /// Whether authentication is disabled (Experimentation mode). Seeded from
  /// [kDefaultAuthDisabled] for a fresh install and overwritten by the
  /// operator's persisted choice once they pick a mode.
  bool _devMode = kDefaultAuthDisabled;

  Future<void> _loadPersistedMode() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getBool(_authDisabledKey);
    if (stored != null && stored != _devMode) {
      _devMode = stored;
      notifyListeners();
    }
  }

  Future<void> _persistMode(bool authDisabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_authDisabledKey, authDisabled);
  }

  final Queue<RequestLogEntry> _requestLog = Queue<RequestLogEntry>();
  static const int _maxLogEntries = 200;

  Map<R4ResourceType, int> _resourceCounts = {};
  Timer? _countsTimer;
  StreamSubscription<RequestLogEntry>? _logSubscription;

  FhirAntDb get db => _dbService.db;
  ServerStatus get status => _status;
  String? get errorMessage => _errorMessage;
  String? get wifiIp => _wifiIp;
  int get port => _port;
  bool get isRunning => _status == ServerStatus.running;
  bool get devMode => _devMode;

  List<RequestLogEntry> get requestLog =>
      _requestLog.toList().reversed.toList();
  Map<R4ResourceType, int> get resourceCounts =>
      Map.unmodifiable(_resourceCounts);

  String? get serverUrl {
    if (_wifiIp == null || !isRunning) return null;
    return 'http://$_wifiIp:$_port';
  }

  set port(int value) {
    if (_status != ServerStatus.stopped) return;
    _port = value;
    notifyListeners();
  }

  set devMode(bool value) {
    if (_status != ServerStatus.stopped) return;
    _devMode = value;
    // Persist the operator's explicit choice so it survives restarts and no
    // longer follows the ship default.
    unawaited(_persistMode(value));
    notifyListeners();
  }

  Future<void> startServer() async {
    if (_status != ServerStatus.stopped && _status != ServerStatus.error) {
      return;
    }

    _status = ServerStatus.starting;
    _errorMessage = null;
    notifyListeners();

    try {
      await _serverService.start(_port, devMode: _devMode);
      _status = ServerStatus.running;

      // Listen to request log stream
      _logSubscription = _serverService.requestLog?.listen((entry) {
        _requestLog.addLast(entry);
        while (_requestLog.length > _maxLogEntries) {
          _requestLog.removeFirst();
        }
        notifyListeners();
      });

      // Start periodic resource count refresh
      await _refreshResourceCounts();
      _countsTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _refreshResourceCounts(),
      );

      await _detectWifiIp();

      // Start Android foreground service to keep server alive
      if (Platform.isAndroid) {
        await FlutterForegroundTask.startService(
          notificationTitle: 'FHIR ANT Server',
          notificationText: 'Running on port $_port',
        );
      }

      notifyListeners();
    } catch (e) {
      _status = ServerStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> stopServer() async {
    if (_status != ServerStatus.running) return;

    _status = ServerStatus.stopping;
    notifyListeners();

    try {
      // Stop Android foreground service
      if (Platform.isAndroid) {
        await FlutterForegroundTask.stopService();
      }

      _countsTimer?.cancel();
      _countsTimer = null;
      await _logSubscription?.cancel();
      _logSubscription = null;

      await _serverService.stop();
      _status = ServerStatus.stopped;
      notifyListeners();
    } catch (e) {
      _status = ServerStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> _refreshResourceCounts() async {
    try {
      final types = await _dbService.db.getResourceTypes();
      final counts = <R4ResourceType, int>{};
      for (final type in types) {
        counts[type] = await _dbService.db.getResourceCount(type);
      }
      _resourceCounts = counts;
      notifyListeners();
    } catch (_) {
      // Silently ignore — DB may be busy
    }
  }

  Future<void> _detectWifiIp() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final info = NetworkInfo();
        _wifiIp = await info.getWifiIP();
      }
      // Fallback: try to get any non-loopback IPv4 address
      if (_wifiIp == null) {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
        );
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback) {
              _wifiIp = addr.address;
              return;
            }
          }
        }
      }
    } catch (_) {
      // WiFi IP detection is best-effort
    }
  }

  @override
  void dispose() {
    _countsTimer?.cancel();
    unawaited(_logSubscription?.cancel());
    super.dispose();
  }
}
