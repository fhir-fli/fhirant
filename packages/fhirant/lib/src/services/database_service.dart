import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';

const _encryptionKeyName = 'fhirant_db_encryption_key';

class DatabaseService {
  FhirAntDb? _db;

  FhirAntDb get db {
    if (_db == null) throw StateError('DatabaseService not initialized');
    return _db!;
  }

  bool get isInitialized => _db != null;

  Future<void> initialize() async {
    // Load SQLCipher native library on Android
    if (Platform.isAndroid) {
      open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
    }

    // Get or generate encryption key
    const secureStorage = FlutterSecureStorage();
    var encryptionKey = await secureStorage.read(key: _encryptionKeyName);
    if (encryptionKey == null) {
      // Generate a random key and persist it
      encryptionKey = DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
          Object().hashCode.toRadixString(36);
      await secureStorage.write(key: _encryptionKeyName, value: encryptionKey);
    }

    // Set up DB file in app documents directory
    final docsDir = await getApplicationDocumentsDirectory();
    final dbDir = Directory('${docsDir.path}/fhirant_data');
    if (!dbDir.existsSync()) {
      dbDir.createSync(recursive: true);
    }
    final dbFile = File('${dbDir.path}/fhirant.db');

    final nativeDb = NativeDatabase(
      dbFile,
      setup: (rawDb) {
        rawDb.execute("PRAGMA key = '$encryptionKey';");
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
