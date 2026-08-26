import 'package:fhirant/src/services/database_service.dart';
import 'package:fhirant_secure_storage/fhirant_secure_storage.dart';
import 'package:fhirant_server/fhirant_server.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _jwtSecretKey = 'fhirant_jwt_secret';

class ServerService {
  ServerService(this._dbService);
  final DatabaseService _dbService;
  FhirAntServer? _server;

  /// SHA-256 fingerprint of the certificate the running server presents.
  ///
  /// The certificate is self-signed and issued for `localhost`, so a client
  /// reaching this phone at its address on the network cannot validate it by
  /// name. It pins this instead, which is why the value is published with the
  /// connection details rather than kept private.
  String? _certificateFingerprint;

  String? get certificateFingerprint => _certificateFingerprint;

  bool get isRunning => _server?.isRunning ?? false;
  bool get devMode => _server?.devMode ?? false;
  int? get port => _server?.port;

  Stream<RequestLogEntry>? get requestLog => _server?.requestLog;

  Future<void> start(int port, {bool devMode = false}) async {
    if (_server?.isRunning ?? false) return;

    // Get or generate the JWT secret, persisted in platform secure storage
    // (Keystore/Keychain-backed). Generated with cryptographic randomness —
    // a predictable, timestamp-derived secret would let tokens be forged.
    const secureStorage = FlutterSecureStorage();
    var jwtSecret = await secureStorage.read(key: _jwtSecretKey);
    if (jwtSecret == null || jwtSecret.isEmpty) {
      jwtSecret = JwtSecret.generate();
      await secureStorage.write(key: _jwtSecretKey, value: jwtSecret);
    }

    final exportDir = await _dbService.getExportDir();

    _server = FhirAntServer(
      _dbService.db,
      jwtSecret: jwtSecret,
      exportDir: exportDir,
      maxRequests: 100,
      devMode: devMode,
    );

    // HTTPS, not HTTP. Everything this server carries is patient data, and
    // the network it is reached over is whatever ad-hoc WiFi happens to exist
    // — cleartext there is readable by anyone associated to the same access
    // point. The certificate is self-signed because there is no CA and no
    // connectivity to reach one; clients pin its fingerprint.
    final tls = await SecureStorageService().loadOrCreateTlsIdentity();
    _certificateFingerprint =
        SecureStorageService.certificateFingerprint(tls.certificate);

    await _server!.startHttps(port, tls.privateKey, tls.certificate);
  }

  Future<void> stop() async {
    await _server?.stop();
    _server = null;
    _certificateFingerprint = null;
  }
}
