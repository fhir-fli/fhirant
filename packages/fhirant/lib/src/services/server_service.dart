import 'package:fhirant_server/fhirant_server.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'database_service.dart';

const _jwtSecretKey = 'fhirant_jwt_secret';

class ServerService {
  final DatabaseService _dbService;
  FhirAntServer? _server;

  ServerService(this._dbService);

  bool get isRunning => _server?.isRunning ?? false;
  bool get devMode => _server?.devMode ?? false;
  int? get port => _server?.port;

  Stream<RequestLogEntry>? get requestLog => _server?.requestLog;

  Future<void> start(int port, {bool devMode = false}) async {
    if (_server?.isRunning ?? false) return;

    // Get or generate JWT secret
    const secureStorage = FlutterSecureStorage();
    var jwtSecret = await secureStorage.read(key: _jwtSecretKey);
    if (jwtSecret == null) {
      jwtSecret = DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
          Object().hashCode.toRadixString(36) +
          DateTime.now().millisecondsSinceEpoch.toRadixString(16);
      await secureStorage.write(key: _jwtSecretKey, value: jwtSecret);
    }

    final exportDir = await _dbService.getExportDir();

    _server = FhirAntServer(
      _dbService.db,
      jwtSecret: jwtSecret,
      exportDir: exportDir,
      maxRequests: 100,
      rateLimitDuration: const Duration(seconds: 60),
      devMode: devMode,
    );

    await _server!.startHttp(port);
  }

  Future<void> stop() async {
    await _server?.stop();
    _server = null;
  }
}
