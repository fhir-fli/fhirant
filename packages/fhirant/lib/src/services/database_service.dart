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

    // Set up DB file in app documents directory
    final docsDir = await getApplicationDocumentsDirectory();
    final dbDir = Directory('${docsDir.path}/fhirant_data');
    if (!dbDir.existsSync()) {
      dbDir.createSync(recursive: true);
    }
    final dbFile = File('${dbDir.path}/fhirant.db');

    // SQLite is built from the sqlite3mc source (SQLite3 Multiple Ciphers)
    // via the build hook declared in pubspec.yaml. The cipher/legacy PRAGMAs
    // select the SQLCipher-v4-compatible scheme so databases created by the
    // previous sqlcipher_flutter_libs builds keep opening.
    final nativeDb = NativeDatabase(
      dbFile,
      setup: (rawDb) {
        rawDb
          ..execute("PRAGMA cipher = 'sqlcipher';")
          ..execute('PRAGMA legacy = 4;')
          ..execute("PRAGMA key = '$encryptionKey';");
        rawDb.config.doubleQuotedStringLiterals = false;
      },
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
