import 'package:drift/drift.dart';

/// Define the logs table
class Logs extends Table {
  /// ID column
  IntColumn get id => integer().autoIncrement()();

  /// Level column
  TextColumn get level =>
      text().withLength(min: 4, max: 10)(); // INFO, WARNING, ERROR
  /// Message column
  TextColumn get message => text()();

  /// Method column
  TextColumn get method => text().nullable()(); // GET, POST, etc.

  /// URL column
  TextColumn get url => text().nullable()(); // Request URL

  /// Status code column
  IntColumn get statusCode => integer().nullable()();

  /// Response time column
  IntColumn get responseTime => integer().nullable()(); // In milliseconds

  /// Client IP column
  TextColumn get clientIp => text().nullable()();

  /// User column
  TextColumn get user => text().nullable()(); // User making request

  /// Stack trace column
  TextColumn get stackTrace => text().nullable()(); // Only for errors

  /// Timestamp column
  DateTimeColumn get timestamp => dateTime().clientDefault(DateTime.now)();
}
