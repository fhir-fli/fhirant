import 'package:drift/drift.dart';

/// Table for storing user accounts for authentication
class Users extends Table {
  /// Auto-incrementing primary key
  IntColumn get id => integer().autoIncrement()();

  /// Unique username (3-100 characters)
  TextColumn get username => text().withLength(min: 3, max: 100).unique()();

  /// Hashed password
  TextColumn get passwordHash => text()();

  /// Salt used for password hashing
  TextColumn get salt => text()();

  /// User role: admin, clinician, or readonly
  TextColumn get role => text().withDefault(const Constant('clinician'))();

  /// Whether the user account is active
  BoolColumn get active => boolean().withDefault(const Constant(true))();

  /// When the account was created
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  /// Last login timestamp
  DateTimeColumn get lastLogin => dateTime().nullable()();
}
