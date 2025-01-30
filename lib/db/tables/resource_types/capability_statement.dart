import 'package:drift/drift.dart';
import 'package:fhir_r4/fhir_r4.dart';

@DataClassName('CapabilityStatementDrift')
/// [CapabilityStatement]Table for Drift
class CapabilityStatementTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  /// URL column
  TextColumn get url => text().nullable()();

  /// Status column
  TextColumn get status => text()();

  /// Date column
  IntColumn get date => integer().nullable()();

  /// Title column
  TextColumn get title => text().nullable()();

  /// Indexes
  List<Set<Column>> get indexes => [
    {url},
    {status},
  ];

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CapabilityStatementHistoryDrift')
/// [CapabilityStatement]HistoryTable for Drift
class CapabilityStatementHistoryTable extends Table {
  /// ID column
  TextColumn get id => text()();

  /// Last updated column
  IntColumn get lastUpdated => integer()();

  /// Resource column
  TextColumn get resource => text()();

  @override
  Set<Column> get primaryKey => {id, lastUpdated};
}
