import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_secure_storage/fhirant_secure_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

const _encryptionKeyName = 'fhirant_db_encryption_key';

class DatabaseService {
  FhirAntDb? _db;

  FhirAntDb get db {
    if (_db == null) throw StateError('DatabaseService not initialized');
    return _db!;
  }

  bool get isInitialized => _db != null;

  Future<void> initialize() async {
    // Get or generate encryption key
    const secureStorage = FlutterSecureStorage();
    var encryptionKey = await secureStorage.read(key: _encryptionKeyName);
    if (encryptionKey == null) {
      // Cryptographic randomness, for the same reason the JWT secret uses it:
      // this key encrypts the patient database, and the previous
      // microsecondsSinceEpoch + Object().hashCode construction was guessable
      // — the timestamp narrows to whenever the app was first run, and an
      // identity hash code is not random and carries very little entropy.
      encryptionKey = SecureStorageService.generateEncryptionKey();
      await secureStorage.write(key: _encryptionKeyName, value: encryptionKey);
    }

    // Bound here, outside the setup closure, where the null check above
    // has promoted the key.
    final storeKey = encryptionKey;

    // Set up DB file in app documents directory
    final docsDir = await getApplicationDocumentsDirectory();
    final dbDir = Directory('${docsDir.path}/fhirant_data');
    if (!dbDir.existsSync()) {
      dbDir.createSync(recursive: true);
    }
    final dbFile = File('${dbDir.path}/fhirant.db');

    // SQLite is built from the sqlite3mc source (SQLite3 Multiple Ciphers)
    // via the build hook declared in pubspec.yaml. `applyStoreCipher`
    // (fhirant_db) is the one place the store's cipher configuration is
    // written; the CLI opens its store with the same call.
    //
    // The store runs on its own isolate (REVIEW-2026-09-06 §6.1): every SQL
    // statement used to execute on the UI isolate, so a search, a count, an
    // export or the specification load held the interface for its duration
    // (0.5–1.1 s at a stretch measured for the load, row 43). Measured
    // 2026-09-08 on the 929k MIMIC copy, same isolate against background:
    // a round trip costs 0.07 ms (`SELECT 1` ×200: 1–5 ms → 14–20 ms) and a
    // real query nothing visible (100 single reads 22 → 26 ms, a token page
    // 12 → 6 ms, a count 70 → 73 ms, RSS unchanged). The JSON decode of
    // each row still happens on the caller.
    final nativeDb = NativeDatabase.createInBackground(
      dbFile,
      setup: (rawDb) => applyStoreCipher(rawDb, storeKey),
    );

    _db = FhirAntDb(nativeDb);
    await _db!.initialize();
  }

  /// Get the export directory path (for bulk data export files).
  Future<String> getExportDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${docsDir.path}/fhirant_export');
    if (!exportDir.existsSync()) {
      exportDir.createSync(recursive: true);
    }
    return exportDir.path;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
