import 'dart:io';
import 'package:fhirant/db/db.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';

/// Service to interact with the SQLite database
class DbService {
  /// Constructor to initialize the database
  DbService() {
    _db = _initializeDatabase();
  }

  static const _databaseName = 'fhir_clinical.db';
  late final Database _db;

  Database _initializeDatabase() {
    final dbPath = path.join(Directory.current.path, _databaseName);
    final db = sqlite3.open(dbPath);

    createTables(db);

    return db;
  }

  /// Closes the database connection
  void close() {
    _db.dispose();
  }
}
