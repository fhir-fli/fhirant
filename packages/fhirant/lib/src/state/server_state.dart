import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' show R4ResourceType;
import 'package:fhirant_server/fhirant_server.dart' show RequestLogEntry;
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../services/database_service.dart';
import '../services/server_service.dart';

enum ServerStatus { stopped, starting, running, stopping, error }

class ServerState extends ChangeNotifier {
  final DatabaseService _dbService;
  final ServerService _serverService;

  ServerStatus _status = ServerStatus.stopped;
  String? _errorMessage;
  String? _wifiIp;
  int _port = 8080;

  final Queue<RequestLogEntry> _requestLog = Queue<RequestLogEntry>();
  static const int _maxLogEntries = 200;

  Map<R4ResourceType, int> _resourceCounts = {};
  Timer? _countsTimer;
  StreamSubscription<RequestLogEntry>? _logSubscription;

  ServerState({
    required DatabaseService dbService,
    required ServerService serverService,
  })  : _dbService = dbService,
        _serverService = serverService {
    _detectWifiIp();
  }

  ServerStatus get status => _status;
  String? get errorMessage => _errorMessage;
  String? get wifiIp => _wifiIp;
  int get port => _port;
  bool get isRunning => _status == ServerStatus.running;

  List<RequestLogEntry> get requestLog => _requestLog.toList().reversed.toList();
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

  Future<void> startServer() async {
    if (_status != ServerStatus.stopped && _status != ServerStatus.error) return;

    _status = ServerStatus.starting;
    _errorMessage = null;
    notifyListeners();

    try {
      await _serverService.start(_port);
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
    _logSubscription?.cancel();
    super.dispose();
  }
}
