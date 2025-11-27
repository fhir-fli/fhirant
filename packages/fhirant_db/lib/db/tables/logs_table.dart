import 'package:drift/drift.dart';

/// Define the logs table with HIPAA-compliant audit logging fields
class Logs extends Table {
  /// ID column
  IntColumn get id => integer().autoIncrement()();

  /// Level column
  TextColumn get level =>
      text().withLength(min: 4, max: 10)(); // INFO, WARNING, ERROR
  
  /// Message column
  TextColumn get message => text()();

  /// Event type for HIPAA audit logging
  /// Values: authentication, phi_access, security, system
  TextColumn get eventType => text().nullable()();

  /// Method column
  TextColumn get method => text().nullable()(); // GET, POST, PUT, PATCH, etc.

  /// URL column
  TextColumn get url => text().nullable()(); // Request URL

  /// Status code column
  IntColumn get statusCode => integer().nullable()();

  /// Response time column
  IntColumn get responseTime => integer().nullable()(); // In milliseconds

  /// Client IP column
  TextColumn get clientIp => text().nullable()();

  /// User column (user ID or username)
  TextColumn get user => text().nullable()();

  /// Resource type accessed (for PHI access logging)
  TextColumn get resourceType => text().nullable()();

  /// Resource ID accessed (for PHI access logging)
  TextColumn get resourceId => text().nullable()();

  /// Action performed (read, create, update, patch, delete, search, history)
  TextColumn get action => text().nullable()();

  /// User agent from request
  TextColumn get userAgent => text().nullable()();

  /// Session ID for tracking user sessions
  TextColumn get sessionId => text().nullable()();

  /// Purpose of use (for HIPAA compliance)
  TextColumn get purposeOfUse => text().nullable()();

  /// Outcome of the operation (success, failure)
  TextColumn get outcome => text().nullable()();

  /// Additional data as JSON string
  TextColumn get additionalData => text().nullable()();

  /// Stack trace column (only for errors)
  TextColumn get stackTrace => text().nullable()();

  /// Timestamp column
  DateTimeColumn get timestamp => dateTime().clientDefault(DateTime.now)();
}
