import 'package:fhirant/sqflite/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Service to interact with the SQLite database using sqflite
class SqfliteDbService {
  static const _databaseName = 'fhir_clinical_sqflite.db';
  static const _databaseVersion = 1;
  static Database? _db;

  /// Initialize the database
  Future<Database> _initializeDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _databaseName);

    return openDatabase(
      path,
      version: _databaseVersion,
      onCreate: (db, version) async {
        // Create tables on database creation
        createTables(db);
      },
    );
  }

  /// Get the database instance (lazy initialization)
  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initializeDatabase();
    return _db!;
  }


  /// Save a single resource
  Future<bool> saveAppointment(Map<String, dynamic> resource) async {
    final db = await database;

    try {
      // Check if the resource exists
      final existingResource = await db.query(
        'Appointment',
        where: 'id = ?',
        whereArgs: [resource['id']],
      );

      if (existingResource.isNotEmpty) {
        // Save the old version in the history table
        final oldResource = existingResource.first;
        await db.insert(
          'AppointmentHistory',
          {
            'id': oldResource['id'],
            'lastUpdated': oldResource['lastUpdated'],
            'resource': oldResource['resource'],
          },
        );
      }

      // Insert the new version in the main table
      await db.insert(
        'Appointment',
        resource,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      return true;
    } catch (e) {
      // Log the error
      print('Error saving Appointment resource: $e');
      return false;
    }
  }

  /// Retrieve an Appointment resource by ID
  Future<Map<String, dynamic>?> getAppointment(String id) async {
    final db = await database;

    try {
      final result = await db.query(
        'Appointment',
        where: 'id = ?',
        whereArgs: [id],
      );

      if (result.isNotEmpty) {
        return result.first;
      }
    } catch (e) {
      print('Error retrieving Appointment resource: $e');
    }

    return null;
  }

  /// Close the database connection
  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
