import 'package:drift/drift.dart';

/// Table for tracking bulk data export jobs.
class ExportJobs extends Table {
  /// UUID job identifier (primary key)
  TextColumn get jobId => text()();

  /// Job status: pending, in_progress, completed, error, cancelled
  TextColumn get status => text().withDefault(const Constant('pending'))();

  /// Original request URL for the manifest
  TextColumn get requestUrl => text()();

  /// Snapshot time (set at kick-off)
  DateTimeColumn get transactionTime => dateTime()();

  /// When the job was created
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  /// When the job completed (nullable)
  DateTimeColumn get completedAt => dateTime().nullable()();

  /// JSON array of {type, url, count} when complete
  TextColumn get outputJson => text().nullable()();

  /// JSON array of OperationOutcome NDJSON files
  TextColumn get errorJson => text().nullable()();

  /// Comma-separated resource type filter
  TextColumn get resourceTypes => text().nullable()();

  /// _since filter value
  DateTimeColumn get since => dateTime().nullable()();

  /// Export level: 'system', 'patient', or 'group'
  TextColumn get exportLevel => text()();

  /// Patient ID for patient-level exports
  TextColumn get patientId => text().nullable()();

  /// Group ID for group-level exports
  TextColumn get groupId => text().nullable()();

  /// Username from auth context
  TextColumn get requestedBy => text().nullable()();

  @override
  Set<Column> get primaryKey => {jobId};
}
